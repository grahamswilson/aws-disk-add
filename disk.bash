#!/bin/bash

#set -xv

add_new_disk () {

# Set SIZE to be the parameter passed to this function
SIZE=$1

# Get a list of current devices seen by the OS for later comparison after new disk is added
CURRENTDISKS=($(lsblk -a | grep -v ^NAME | grep -v ^'├' | grep -v ^'└' | awk '{print $1}'))

echo ${CURRENTDISKS[@]}

# Get my AWS Instance-ID
INSTANCE=$(curl -q -s http://169.254.169.254/latest/meta-data/instance-id)

# Get what AWS Region I am in
REGION=$(curl -q -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

# Get a list of current AWS volumes I have
volumes=($(/usr/local/bin/aws ec2 describe-volumes --region ${REGION%?} --filters "Name=attachment.instance-id,Values=$INSTANCE" | grep \"Device\"\:  | awk '{print $2}' | sed 's/[",]//g'))

echo ${volumes[*]}

# Looping through possible new AWS volume device names searching for the first one that isn't in my current list of attached volumes
for newdiskname in f g h i j k l m n o p q r s t u v w x y z
do

if [[ " ${volumes[*]} " =~ " /dev/sd${newdiskname} " ]] || [[ " ${volumes[*]} " =~ " /dev/xvd${newdiskname} " ]]
then
echo Either /dev/sd${newdiskname} or /dev/xvd${newdiskname} is already attached to this instace.
else
break
fi
done

echo /dev/sd${newdiskname} or  /dev/xvd${newdiskname} is available for use.

# Now lets create a new volume with that unused AWS device name
VOLUME=$(/usr/local/bin/aws ec2 create-volume --availability-zone ${REGION} --size ${SIZE} --volume-type gp2 --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${newdiskname}}]" | grep \"VolumeId\"\:  | awk '{print $2}' | sed 's/[",]//g')

# Lets wait for that to finish before moving on
/usr/local/bin/aws ec2 wait volume-available --volume-ids ${VOLUME}

# Now attach the new volume to me - note we choose the /dev/sd prefix as that is preferred
/usr/local/bin/aws ec2 attach-volume --volume-id ${VOLUME} --device /dev/sd${newdiskname} --instance-id ${INSTANCE}

# Lets wait for that to finish before moving on
/usr/local/bin/aws ec2 wait volume-in-use --volume-ids ${VOLUME}

# Now we saw that sometimes it takes a second or two for a new OS device file to be created so lets wait before giving up...
for count in {1..30}
do 
NEWDISKS=($(lsblk -a | grep -v ^NAME | grep -v ^'├' | grep -v ^'└' | awk '{print $1}'))
echo ${NEWDSISKS[@]}
if [[ "${NEWDISKS[@]}" ==  "${CURRENTDISKS[@]}" ]]
then
echo sleeping for 1 second
sleep 1
else
break
fi
done

# Now we just compare this new list with the original list and anything new must be our new disk
NEWDEVICE=($(echo ${NEWDISKS[@]} ${CURRENTDISKS[@]} | tr ' ' '\n' | sort | uniq -u))

echo ${NEWDEVICE[@]}

# If after waiting we still dont see any new device, we need to exit
if [[ "${NEWDEVICE[@]}" == "" ]]
then
echo No new device file found after waiting
exit
fi

# Lets just double check there is only one NEWDEVICE and if not lets exit as something isn't right
if [[ `echo ${NEWDEVICE[@]} | awk '{print $2}'` == "" ]]
then
echo No second disk
else echo More than one - panic
exit
fi

# Now lets check if this new disk is unpartitioned before we partition it
if [[ $(/sbin/sfdisk -d /dev/${NEWDEVICE} 2>/dev/null) == "" ]]
then
#echo "Device not partitioned"
#/sbin/parted /dev/${NEWDEVICE} mklabel gpt --script
#/sbin/parted /dev/${NEWDEVICE} mkpart primary 0% 100% --script
echo No partition necessary for XFS
# Assumine the use of xfs but could add lvm2 - if its installed - to do pvcreate etc
mkfs.xfs /dev/${NEWDEVICE}
mkdir $MOUNT
UUID=($(xfs_admin -u /dev/${NEWDEVICE} | sed 's/\ //g' | cut -f2 -d"="))
cat >> /etc/fstab << EOF
UUID=${UUID}	$MOUNT		xfs    defaults        1 2
#/dev/$NEWDEVICE	$MOUNT          xfs    defaults        1 2
EOF
mount $MOUNT
else
echo Disk seems to have a partition so existing rapidly
exit
fi

}


modify_existing_disk () {
echo Under construction
exit
}


case $1 in

  add)

	if [[ ! -f /usr/local/bin/aws ]]
	then
	echo Looks like you need to install AWS CLI so let me take care of that for you
	cd /tmp
	yum install -y unzip
	curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
	unzip awscliv2.zip
	./aws/install
	rm -f /tmp/awscliv2.zip
	rm -rf /tmp/aws
	cd ~
	fi

	/usr/local/bin/aws ec2 describe-instances > /dev/null 2>&1
	if [[ "$?" != "0" ]]
	then
	echo Looks like you may need to fix AWS CLI permissions
	exit
	fi
	
	SIZE=$2
	if [[ $SIZE == "" ]]
	then
	echo Need to give me a size, in GB
	exit
	fi

	if [ "$SIZE" -eq "$SIZE" ] && [[ "$SIZE" != "0" ]] 2> /dev/null
	then
	echo "Input contains integer"
	else
	echo "Input is not a non zero integer"
	exit
	fi

        MOUNT=$3
        if [[ $MOUNT == "" ]]
        then
        echo Need to give me a mount point name like /u01
        exit
        fi

        if [[ "${MOUNT:0:1}" == "/" ]]
        then
        echo "Leading / found as expected"
        else
        echo "No leading / found and I am not adding one for you"
        exit
        fi

	if [[ -d $MOUNT ]]
	then
	echo Mount already exists so I am stopping right here
	exit
	fi

	grep -v ^# /etc/fstab | grep -v ^$ | awk '{print $2}' | grep ^${MOUNT}$ && {
	echo Found that mount point already listed in fstab so stopping
	exit
	}

###	ACTION=add
	add_new_disk $SIZE $MOUNT
    ;;

  modify)
	echo modify
###	ACTION=modify
	modify_existing_disk
	exit
    ;;

  *)
	echo Need to add an action - add or modify
	exit
    ;;

esac



