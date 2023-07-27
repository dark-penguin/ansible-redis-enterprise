Role Name
=========

This is a role and an example playbook to deploy Redis Enterprise (trial) on any number of nodes, and create a geodistributed database. It is not production-ready - just finicking around.

This role allows adding new nodes to the CDRB. It automatically figured out if a CRDB is already present on any existing nodes, and adds all instances where it is not. However, it does not handle anything related to removing failed nodes or re-adding previously failed nodes. That should be handled manually depending on the situation, so that's out of scope.

Notes
-----

- Redis Enterprise is deployed using the official Docker images.
- Redis Enterprise only supports Docker with "--net host" mode.

Tests
-----

Tests are included as a shell script.

Since the role is deployed with Docker, it can not be easily tested with Docker. It is expected that you have some testing infrastructure (e.g. Vagrant) that you can test on. Setting up Vagrant for testing can not be included because at the moment the Vagrant provider for Molecule is unsupported and does not work (at least in my case, with libvirt).

The test script looks for an inventory in `./hosts`, which should only contain one group (specified in the playbook). All hosts found in the inventory are used for the integration tests (setting and removing values on each host).

While Ansible does not provide a way to pass a Vault password as an environment variable (which is the usual way of doing it in CI), this script fixes that. It looks for the Vault password in `ANSIBLE_VAULT_PASSWORD` environment variable, saves it into a file in /tmp , and then sets `ANSIBLE_VAULT_PASSWORD_FILE` pointing to that file. The ephemeral password file is removed after either all tests succeed, or any test fails.

Unfortunately, it is impossible to test for proper replication due to the specifics of Redis Enterprise CRDB replication. After setting keys on one node, they can appear on some other nodes immediately, but take a very long time to appear on some other nodes. Because of this, it is not possible to try setting keys on one host and expect to be able to read them from any other host immediately. We can only try reading each key from the same host it was set on.

Role Variables
--------------

While default secrets are provided in plaintext, they should be overridden by a proper secrets file. An example secrets file is provided (with Vault password set to "password").

The other variables listed in defaults are self-explanatory.

Dependencies
------------

- geerlingguy.docker
