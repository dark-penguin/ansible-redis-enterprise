#!/bin/bash

INVENTORY="hosts"
VAULT_PWFILE="/tmp/pwd.txt"


# Check invocation and prerequisites
error() { echo -e "ERROR: $*" 1>&2; rm -f "$VAULT_PWFILE"; exit 1; }
usage() { echo "USAGE: $0 (with no parameters)" 1>&2; exit 1; }

[ -n "$1" ] && usage
[ ! -f "$INVENTORY" ] && error "Inventory file not found (must be './$INVENTORY')"
[ -z "$ANSIBLE_VAULT_PASSWORD" ] && error "Provide Vault password as ANSIBLE_VAULT_PASSWORD"

for i in yamllint ansible ansible-playbook ansible-lint ansible-vault; do
	which "$i" > /dev/null || error "$i not found"
done

hosts="$(sed 's/\t/ /g' "$INVENTORY" | cut -d ' ' -f1 | grep -v '\[')"
hostgroup="$(grep 'hosts:' deploy_redis.yml | awk '{print $NF}')"
password="$(ansible-vault view secrets.yml | grep 'db_password:' | awk '{print $NF}' | tr -d \")"

# Save the Vault password
touch "$VAULT_PWFILE"
chmod 600 "$VAULT_PWFILE"
echo "$ANSIBLE_VAULT_PASSWORD" > "$VAULT_PWFILE"


# Lint tests
echo " === yamllint: checking... ==="
yamllint . || error "yamllint failed"
echo " === yamllint: passed ==="
echo
echo " === syntax-check: checking... ==="
ANSIBLE_VAULT_PASSWORD_FILE="$VAULT_PWFILE" \
	ansible-playbook --syntax-check deploy_redis.yml \
	|| error "syntax-check failed"
echo " === syntax-check: passed ==="
echo
echo " === ansible-lint: checking... ==="
ANSIBLE_VAULT_PASSWORD_FILE="$VAULT_PWFILE" \
	ansible-lint \
	|| error "ansible-lint failed"
echo " === ansible-lint: passed ==="
echo


# Deploy
echo " === Deploying... ==="
ANSIBLE_VAULT_PASSWORD_FILE="$VAULT_PWFILE" \
	ansible-playbook -i "$INVENTORY" deploy_redis.yml \
	|| error "Deployment failed"
echo " === Deployment: success ==="
echo


# Validate
echo " === Validation... ==="
echo " === Setting keys... ==="
# Set keys on each host
for i in $hosts; do
	command="docker exec -it -e REDISCLI_AUTH=\"$password\" redis
		redis-cli -p 12000 set \"key-$i\" \"value-$i\""
	ansible -i "$INVENTORY" "$i" -b -a "$command" \
		|| error "Validation failed: setting key on host '$i'"
done


# # Read those keys on each host
# # This is better to do sequentially - better output in case of failure
# # This can not succeed because of Redis synchronization features!
# echo " === Retrieving keys... ==="
# for i in $hosts; do
# 	for j in $hosts; do
# 		command="/bin/bash -c '[ \"\$(docker exec -it -e REDISCLI_AUTH=\"$password\" redis \
# 			redis-cli -p 12000 get \"key-$j\" | cut -d \\\" -f2 )\" == \"value-$j\" ] '"

# 		ansible -i "$INVENTORY" "$i" -b -m shell -a "$command" \
# 			|| error "Validation failed: retrieving key '$j' from host '$i'"
# 	done
# done


# All we can do is read those keys from the same host
echo " === Retrieving keys... ==="
for i in $hosts; do
	command="/bin/bash -c '[ \"\$(docker exec -it -e REDISCLI_AUTH=\"$password\" redis \
		redis-cli -p 12000 get \"key-$i\" | cut -d \\\" -f2 )\" == \"value-$i\" ] '"

	ansible -i "$INVENTORY" "$i" -b -m shell -a "$command" \
		|| error "Validation failed: retrieving key '$i' from host '$i'"
done


# Remove those keys
echo " === Removing keys... ==="
for i in $hosts; do
	command="docker exec -it -e REDISCLI_AUTH=\"$password\" redis
		redis-cli -p 12000 del \"key-$i\""
	ansible -i "$INVENTORY" "$i" -b -a "$command" \
		|| error "Validation failed: deleting key on host '$i'"
done
echo " === Validation: success ==="
echo


# Clean up containers
echo " === Clean up containers... ==="
ansible -i "$INVENTORY" "$hostgroup" -b -m shell -a "docker stop redis; docker rm redis"
# No need to check the return values here
echo -e "\n\n === All checks passed\n"

rm "$VAULT_PWFILE"
