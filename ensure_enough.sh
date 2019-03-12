#!/bin/bash
VGGP_IMAGE=vggp-v31-j101-2deef7cb2572-master

# Static things
USER_DATA=userdata.yml
IMAGE_ID=$(openstack image show $VGGP_IMAGE -f json | jq .id -r)


remote_command() {
	remote_host=$1; shift

	ssh centos@$remote_host "$@"

}

non_conflicting_name() {
	date --rfc-3339=ns | sha256sum | head -c 20
}


identify_to_keep() {
	group=$1; shift
	openstack server list --name vgcnbwc-$group -f json | \
		jq -r ".[] | select((.Image == \"${VGGP_IMAGE}\") and (.Status == \"ACTIVE\")) | .ID"
}

identify_to_remove() {
	group=$1; shift
	openstack server list --name vgcnbwc-$group -f json | \
		jq -r ".[] | select((.Image != \"${VGGP_IMAGE}\") or (.Status != \"ACTIVE\")) | .ID"
}

identify_server_group() {
	echo
}


wait_for_state() {

		echo
}

launch_server() {
	name=$1; shift
	flavor=$1; shift
	group=$1; shift
	is_training=$1; shift

	userdata=`mktemp`

	cat $USER_DATA | \
		sed "s/GalaxyTraining = True/GalaxyTraining = $is_training/g" | \
		sed "s/GalaxyGroup = training-beta/GalaxyGroup = $group/g" | \
		> $userdata


	openstack server create \
		--key-name cloud2 \
		# Bioinf NIC
		--nic net-id="afca9459-0eb1-4d67-999f-b07bf3bc99c5" \
		--image "$IMAGE_ID" \
		--flavor "$flavor"  \
		--wait \
		"$name_vm" \
		"$@"

}

gracefully_terminate() {
	echo "NOP; TODO"
}

top_up() {
	prefix=$1; shift
	desired_instances=$1; shift
	flavor=$1; shift

	servers_to_keep="$(identify_to_keep $prefix | wc -l)"

	if (( desired_instances < servers_to_keep )); then
		to_launch=$((desired_instances - servers_to_keep));
		for ((i=0; i<to_launch; i++)); do
			launch_server
		done
	fi
}

y2j() {
	python -c 'import sys; import yaml; import json; sys.stdout.write(json.dumps(yaml.load(sys.stdin), indent=2))'
}

syncronize_infrastructure() {
	for group in $(cat resources.yaml | y2j | jq -r '.deployment | keys[]'); do
		echo "Processing $group"
		# Group properties
		flavor=$(cat resources.yaml | y2j | jq -r ".deployment.\"${group}\".flavor")
		count=$(cat resources.yaml | y2j | jq -r ".deployment.\"${group}\".count")

		servers_ok=$(identify_to_keep $group | wc -l)

		for server in $(identify_to_remove $group); do
			echo ">$server<"
		done

		if (( servers_ok < count )); then
			top_up
		fi
	done
}


syncronize_infrastructure
