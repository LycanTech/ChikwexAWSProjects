#!/usr/bin/env python3
"""
Custom Dynamic Inventory Script for Chikwex Infrastructure

This script provides a custom inventory source that can:
- Fetch instances from AWS EC2
- Apply custom filtering and grouping logic
- Integrate with AWS Systems Manager for connectivity checks
- Support multiple environments and regions

Usage:
    ./custom_inventory.py --list
    ./custom_inventory.py --host <hostname>
"""

import argparse
import json
import os
import sys
from typing import Any

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError
except ImportError:
    print("Error: boto3 is required. Install with: pip install boto3", file=sys.stderr)
    sys.exit(1)


class ChikwexInventory:
    """Custom inventory class for Chikwex Infrastructure."""

    def __init__(self):
        """Initialize the inventory with AWS clients."""
        self.inventory = {
            "_meta": {"hostvars": {}},
            "all": {"children": ["ungrouped"]},
            "ungrouped": {"hosts": []},
        }

        # Configuration from environment
        self.environment = os.getenv("CHIKWEX_ENV", "dev")
        self.project_tag = os.getenv("CHIKWEX_PROJECT", "chikwex-infra")
        self.regions = os.getenv("AWS_REGIONS", "us-east-1").split(",")
        self.use_private_ip = os.getenv("USE_PRIVATE_IP", "true").lower() == "true"

        # Initialize AWS clients
        self.ec2_clients = {}
        self.ssm_clients = {}

        for region in self.regions:
            try:
                self.ec2_clients[region] = boto3.client("ec2", region_name=region)
                self.ssm_clients[region] = boto3.client("ssm", region_name=region)
            except NoCredentialsError:
                print(f"Warning: No AWS credentials found for region {region}", file=sys.stderr)

    def get_instances(self) -> list[dict[str, Any]]:
        """Fetch EC2 instances from all configured regions."""
        instances = []

        filters = [
            {"Name": "instance-state-name", "Values": ["running"]},
            {"Name": "tag:Project", "Values": [self.project_tag]},
            {"Name": "tag:Environment", "Values": [self.environment, f"{self.environment}*"]},
        ]

        for region, client in self.ec2_clients.items():
            try:
                paginator = client.get_paginator("describe_instances")
                for page in paginator.paginate(Filters=filters):
                    for reservation in page["Reservations"]:
                        for instance in reservation["Instances"]:
                            instance["_region"] = region
                            instances.append(instance)
            except ClientError as e:
                print(f"Error fetching instances from {region}: {e}", file=sys.stderr)

        return instances

    def get_ssm_managed_instances(self, region: str) -> set[str]:
        """Get list of instances managed by SSM."""
        managed = set()

        try:
            client = self.ssm_clients.get(region)
            if client:
                paginator = client.get_paginator("describe_instance_information")
                for page in paginator.paginate():
                    for info in page["InstanceInformationList"]:
                        if info.get("PingStatus") == "Online":
                            managed.add(info["InstanceId"])
        except ClientError as e:
            print(f"Warning: Could not fetch SSM info for {region}: {e}", file=sys.stderr)

        return managed

    def get_instance_tags(self, instance: dict) -> dict[str, str]:
        """Extract tags from an instance as a dictionary."""
        tags = {}
        for tag in instance.get("Tags", []):
            tags[tag["Key"]] = tag["Value"]
        return tags

    def get_hostname(self, instance: dict, tags: dict) -> str:
        """Determine the hostname for an instance."""
        # Priority: Name tag > private IP > instance ID
        if "Name" in tags and tags["Name"]:
            # Sanitize the name for Ansible
            return tags["Name"].replace(" ", "-").lower()
        if instance.get("PrivateIpAddress"):
            return instance["PrivateIpAddress"]
        return instance["InstanceId"]

    def add_host_to_group(self, group: str, hostname: str) -> None:
        """Add a host to a group, creating the group if necessary."""
        if group not in self.inventory:
            self.inventory[group] = {"hosts": [], "children": []}
            # Add to all.children if not a child group
            if group not in self.inventory["all"]["children"]:
                self.inventory["all"]["children"].append(group)

        if hostname not in self.inventory[group]["hosts"]:
            self.inventory[group]["hosts"].append(hostname)

    def add_child_group(self, parent: str, child: str) -> None:
        """Add a child group to a parent group."""
        if parent not in self.inventory:
            self.inventory[parent] = {"hosts": [], "children": []}
            self.inventory["all"]["children"].append(parent)

        if child not in self.inventory[parent]["children"]:
            self.inventory[parent]["children"].append(child)

    def build_inventory(self) -> None:
        """Build the complete inventory from AWS data."""
        instances = self.get_instances()
        ssm_instances = {}

        # Get SSM managed instances for each region
        for region in self.regions:
            ssm_instances[region] = self.get_ssm_managed_instances(region)

        for instance in instances:
            tags = self.get_instance_tags(instance)
            hostname = self.get_hostname(instance, tags)
            region = instance["_region"]

            # Determine connection IP
            if self.use_private_ip:
                ansible_host = instance.get("PrivateIpAddress", "")
            else:
                ansible_host = instance.get("PublicIpAddress") or instance.get("PrivateIpAddress", "")

            # Build host variables
            hostvars = {
                "ansible_host": ansible_host,
                "ansible_user": self._get_ssh_user(instance, tags),
                "ec2_instance_id": instance["InstanceId"],
                "ec2_instance_type": instance["InstanceType"],
                "ec2_region": region,
                "ec2_availability_zone": instance["Placement"]["AvailabilityZone"],
                "ec2_vpc_id": instance.get("VpcId", ""),
                "ec2_subnet_id": instance.get("SubnetId", ""),
                "ec2_private_ip": instance.get("PrivateIpAddress", ""),
                "ec2_public_ip": instance.get("PublicIpAddress", ""),
                "ec2_security_groups": [sg["GroupId"] for sg in instance.get("SecurityGroups", [])],
                "ec2_tags": tags,
                "ssm_managed": instance["InstanceId"] in ssm_instances.get(region, set()),
            }

            # Add to meta hostvars
            self.inventory["_meta"]["hostvars"][hostname] = hostvars

            # Group by Role tag
            role = tags.get("Role", "").lower()
            if role:
                group_name = f"{role}s" if not role.endswith("s") else role
                self.add_host_to_group(group_name, hostname)

                # Also add role-prefixed group
                self.add_host_to_group(f"role_{role}", hostname)
            else:
                self.add_host_to_group("ungrouped", hostname)

            # Group by Environment tag
            env = tags.get("Environment", self.environment).lower()
            self.add_host_to_group(f"env_{env}", hostname)

            # Group by Region
            self.add_host_to_group(f"region_{region.replace('-', '_')}", hostname)

            # Group by Availability Zone
            az = instance["Placement"]["AvailabilityZone"].replace("-", "_")
            self.add_host_to_group(f"az_{az}", hostname)

            # Group by Instance Type
            itype = instance["InstanceType"].replace(".", "_")
            self.add_host_to_group(f"instance_type_{itype}", hostname)

            # Group by Application tag
            app = tags.get("Application", "").lower()
            if app:
                self.add_host_to_group(f"app_{app}", hostname)

            # Group by Tier tag
            tier = tags.get("Tier", "").lower()
            if tier:
                self.add_host_to_group(f"tier_{tier}", hostname)

            # Group for SSM managed instances
            if hostvars["ssm_managed"]:
                self.add_host_to_group("ssm_managed", hostname)

            # OS-based grouping
            platform = instance.get("Platform", "linux").lower()
            self.add_host_to_group(f"os_{platform}", hostname)

        # Set up parent-child relationships for common groupings
        self._setup_group_hierarchy()

    def _get_ssh_user(self, instance: dict, tags: dict) -> str:
        """Determine the SSH user based on instance attributes."""
        # Check for explicit OS tag
        os_tag = tags.get("OS", "").lower()
        if "ubuntu" in os_tag:
            return "ubuntu"
        if "debian" in os_tag:
            return "admin"
        if "centos" in os_tag:
            return "centos"

        # Check AMI ID for common patterns
        image_id = instance.get("ImageId", "").lower()
        if "ubuntu" in image_id:
            return "ubuntu"

        # Default for Amazon Linux / RHEL
        return "ec2-user"

    def _setup_group_hierarchy(self) -> None:
        """Set up parent-child group relationships."""
        # Environment hierarchy
        for group in list(self.inventory.keys()):
            if group.startswith("env_"):
                self.add_child_group("environments", group)

        # Region hierarchy
        for group in list(self.inventory.keys()):
            if group.startswith("region_"):
                self.add_child_group("regions", group)

        # Tier hierarchy
        for group in list(self.inventory.keys()):
            if group.startswith("tier_"):
                self.add_child_group("tiers", group)

    def get_host(self, hostname: str) -> dict:
        """Get variables for a specific host."""
        self.build_inventory()
        return self.inventory["_meta"]["hostvars"].get(hostname, {})

    def list_inventory(self) -> dict:
        """Return the complete inventory."""
        self.build_inventory()
        return self.inventory


def main():
    """Main entry point for the inventory script."""
    parser = argparse.ArgumentParser(description="Chikwex Infrastructure Dynamic Inventory")
    parser.add_argument("--list", action="store_true", help="List all hosts and groups")
    parser.add_argument("--host", help="Get variables for a specific host")
    args = parser.parse_args()

    inventory = ChikwexInventory()

    if args.host:
        result = inventory.get_host(args.host)
    elif args.list:
        result = inventory.list_inventory()
    else:
        parser.print_help()
        sys.exit(1)

    print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    main()
