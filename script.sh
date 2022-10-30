#!/bin/sh

set -o errexit
set -o nounset
set -o pipefail

CLUSTER_NAME=${CLUSTER_NAME}
NODEGROUP_NAMES=${NODEGROUP_NAMES:-""}

if [ "$NODEGROUP_NAMES" = "" ]
then
    NODEGROUP_NAMES=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --output text --query "nodegroups[] | join(' ', @)")
else
    NODEGROUP_NAMES=$@
fi

for NODEGROUP_NAME in $NODEGROUP_NAMES
do
    NODEGROUP_DETAILS=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name 
$NODEGROUP_NAME)
    NODEGROUP_STATUS=$(echo $NODEGROUP_DETAILS | jq -r '.nodegroup.status')
    if [ "$NODEGROUP_STATUS" != "ACTIVE" ]; then
        echo "nodegroup $NODEGROUP_NAME is not active, skipping!"
        continue
    fi
    # release version looks like 1.23.9-20220926
    CURRENT_RELEASE_VERSION=$(jq -r '.nodegroup.releaseVersion' $NODEGROUP_DETAILS)
    K8S_VERSION=$(echo $CURRENT_RELEASE_VERSION | cut -f1,2 -d'.')
    AMI_TYPE=$(jq -r '.nodegroup.amiType' $NODEGROUP_DETAILS)
    case $AMI_TYPE in
      AL2_x86_64)
        
SSM_PARAMETER_NAME="/aws/service/eks/optimized-ami/$K8S_VERSION/amazon-linux-2/recommended/release_version"
        ;;
      AL2_ARM_64)
        
SSM_PARAMETER_NAME="/aws/service/eks/optimized-ami/$K8S_VERSION/amazon-linux-2-arm/recommended/release_version"
        ;;
      AL2_x86_64_GPU)
        
SSM_PARAMETER_NAME="/aws/service/eks/optimized-ami/$K8S_VERSION/amazon-linux-2-gpu/recommended/release_version"
        ;;  
      *)
        echo >&2 "$AMI_TYPE nodegroup $NODEGROUP_NAME is not supported and won't be updated!"
        continue
        ;;
    esac
    LATEST_RELEASE_VERSION=$(aws ssm get-parameter --name $SSM_PARAMETER_NAME | jq -r '.Parameter.Value')
    if [ "$CURRENT_RELEASE_VERSION" != "$LATEST_RELEASE_VERSION" ]
    then
        echo "Updating nodegroup $NODEGROUP_NAME from $CURRENT_RELEASE_VERSION to $LATEST_RELEASE_VERSION"
        aws eks update-nodegroup-version \
            --cluster-name $CLUSTER_NAME \
            --nodegroup-name $NODEGROUP_NAME \
            --release-version $NEW_RELEASE_VERSION
    else 
        echo "Nodegroup $NODEGROUP_NAME is already on the latest release version ($LATEST_RELEASE_VERSION)"
    fi
done

