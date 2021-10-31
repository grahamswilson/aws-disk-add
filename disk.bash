#!/bin/bash

set -xv

case $1 in

  add)

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

	ACTION=add

    ;;

  modify)
	echo modify
	ACTION=modify
	exit
    ;;

  *)
	echo Need to add an action - add or modify
	exit
    ;;

esac


if [[ $ACTION == "add" ]]
then

CURRENTDISKS=($(lsblk -a | grep -v ^NAME | grep -v ^'├' | grep -v ^'└' | awk '{print $1}'))

echo ${CURRENTDISKS[@]}

INSTANCE=$(curl -q -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -q -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

volumes=($(/usr/local/bin/aws ec2 describe-volumes --region ${REGION%?} --filters "Name=attachment.instance-id,Values=$INSTANCE" | grep \"Device\"\:  | awk '{print $2}' | sed 's/[",]//g'))

echo ${volumes[*]}

for newdiskname in f g h i j k l m n o p q r s t u v w x z y
do

if [[ " ${volumes[*]} " =~ " /dev/sd${newdiskname} " ]];
then
	echo /dev/sd${newdiskname} is already attached to this instace.
else
	break
fi
done

echo /dev/sd${newdiskname} is available for use.

VOLUME=$(/usr/local/bin/aws ec2 create-volume --availability-zone ${REGION} --size ${SIZE} --volume-type gp2 --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${newdiskname}}]" | grep \"VolumeId\"\:  | awk '{print $2}' | sed 's/[",]//g')

/usr/local/bin/aws ec2 wait volume-available --volume-ids ${VOLUME}

/usr/local/bin/aws ec2 attach-volume --volume-id ${VOLUME} --device /dev/sd${newdiskname} --instance-id ${INSTANCE}

/usr/local/bin/aws ec2 wait volume-in-use --volume-ids ${VOLUME}

sleep 2

lsblk -a | grep -v ^NAME | grep -v ^'├' | grep -v ^'└' | awk '{print $1}'

NEWDISKS=($(lsblk -a | grep -v ^NAME | grep -v ^'├' | grep -v ^'└' | awk '{print $1}'))

echo ${NEWDISKS[@]}

NEWDEVICE=($(echo ${NEWDISKS[@]} ${CURRENTDISKS[@]} | tr ' ' '\n' | sort | uniq -u))

echo $NEWDEVICE


fi
