#!/bin/bash
 
# Requirements:
# * pcscd needs to be installed.
# * You need to have your OpenPGP public key as a key file or on a key server.
# * The HDD needs to be already encrypted with a password (this can be done via the debian installer).
#
# Things to improve:
# * Check if pcscd is really needed or could be removed.
# * kill -09 is used to kill scdaemon. It would be better to kill the process gently.
# * It is assumed that slot 0 of the encrypted device is the existing password slot. This should be checked before removing the slot.
# * The manipulation of the file /etc/crypttab changes all lines without making sure the lines should really be changed and the manipulation is non-idempotent
 
set -e
set -x
 
# Copy scripts
mkdir -p /etc/initramfs-tools/hooks/
cp cryptgnupg_sc /etc/initramfs-tools/hooks/
mkdir -p /lib/cryptsetup/scripts/
cp decrypt_gnupg_sc /lib/cryptsetup/scripts/
 
# Have root get your public key
echo "The following encryption key could be found on your smartcard:"
gpg --card-status | grep -A 1 "Encryption key"
PUBLIC_KEY_ID=`gpg --card-status | grep "Encryption key" | cut -d ':' -f2- | tr -d ' ' | tr -d '\n'`
PS3="Please choose how to receive the public encryption key: "
OPTIONS=("Receive from key file" "Receive from server" "Quit")
select OPTION in "${OPTIONS[@]}"
do
	case $OPTION in
		"Receive from key file")
			read -p "Please enter the path to the key file: " PUBLIC_KEY_FILE
			gpg --import "$PUBLIC_KEY_FILE"
			break
			;;
		"Receive from server")
			gpg --recv-keys "$PUBLIC_KEY_ID"
			break
			;;
		"Quit")
			exit 1
			;;
		*)
			echo "Invalid option $REPLY"
			exit 1
			;;
	esac
done
 
# Create key file encrypted with both gpg key and password
GPG_TTY=$(tty)
export GPG_TTY
mkdir -p -m 700 /etc/keys
echo "You will be asked to insert a password. This password is used as a fallback for decrypting the HDD (in case you should lose or break your smartcard). Press any key to continue."
read -s -n 1
dd if=/dev/random bs=1 count=256 | gpg -o /etc/keys/cryptkey.gpg -r "$PUBLIC_KEY_ID" -ec
cd /root
rm -f keyfifo
mkfifo -m 700 keyfifo
gpg -d /etc/keys/cryptkey.gpg >keyfifo &
 
cd /root
PS3="The key will now be added to the encrypted device. You will be asked for the password the device is currently encrypted with. You will then be asked for your smart card PIN. Please choose the device to add the smartcard decryption to: "
unset OPTIONS
OPTIONS=$(lsblk --fs --list --paths | grep 'crypto_LUKS' | awk '{print $1}')
select OPTION in "${OPTIONS[@]}" "Quit"; do
	case $OPTION in
		/dev/*)
			ENCRYPTED_DEVICE=$OPTION
			cryptsetup luksAddKey "$ENCRYPTED_DEVICE" keyfifo
			break
			;;
		"Quit")
			exit 1
			;;
		*)
			echo "Invalid option $REPLY"
			exit 1
			;;
	esac
done
rm -f keyfifo
 
gpg --export-options export-minimal --export-secret-keys "$PUBLIC_KEY_ID" | gpg --homedir "/etc/keys/" --import
# For an unknown reason, kindly killing scdaemon does not work at this point. So we use kill -09.
# gpg-connect-agent "SCD KILLSCD" "SCD BYE" /bye
kill -09 `pgrep scdaemon`
gpg --homedir "/etc/keys/" --card-status
 
# For an unknown reason, kindly killing scdaemon does not work at this point. So we use kill -09.
# gpg-connect-agent "SCD KILLSCD" "SCD BYE" /bye
kill -09 `pgrep scdaemon`
echo "We will now test if the decryption script is working. You will be asked for your smart card PIN. Press any key to continue."
read -s -n 1
/lib/cryptsetup/scripts/decrypt_gnupg_sc /etc/keys/cryptkey.gpg > /dev/null
 
awk '{$3 = "/etc/keys/cryptkey.gpg"; print}' /etc/crypttab > /etc/crypttab.tmp.bak && mv /etc/crypttab.tmp.bak /etc/crypttab
awk '{$4 = $4",keyscript=decrypt_gnupg_sc"; print}' /etc/crypttab > /etc/crypttab.tmp.bak && mv /etc/crypttab.tmp.bak /etc/crypttab
 
update-initramfs -u
 
# For an unknown reason, kindly killing scdaemon does not work at this point. So we use kill -09.
# gpg-connect-agent "SCD KILLSCD" "SCD BYE" /bye
kill -09 `pgrep scdaemon`
echo "We will now remove the password slot from the encrypted device. You will be asked for your smart card PIN. Press any key to continue."
read -s -n 1
rm -f keyfifo
mkfifo -m 700 keyfifo
gpg -d /etc/keys/cryptkey.gpg >keyfifo &
cryptsetup --key-file=keyfifo luksKillSlot "$ENCRYPTED_DEVICE" 0
rm -f keyfifo
