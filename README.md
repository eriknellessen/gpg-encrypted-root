# gpg-encrypted-root
Encrypt your root volume with an OpenPGP smartcard

This repository is based on the software and information from [this tutorial](http://digitalbrains.com/2014/gpgcryptroot) by Peter Lebbing.

After the debian stretch release, the scripts were not working anymore. The reason was, that gpg was updated to version 2 in debian stretch. Thus the command line options changed and the call to gpg did not work as expected anymore. I adapted the scripts to the new gpg version.

This mini-guide is for advanced users; I assume you understand all the commands involved. I recommend reading the scripts to see what they are like.
 
Let's assume you used LUKS to put a password on your root volume, for instance by using the Debian installer. We will install a LUKS "password" that is unlocked by an OpenPGP smartcard.
  
So suppose your /etc/crypttab looks something like this:
``` 
mobidisk-crtest_crypt UUID=2b0c0898-a92d-48ac-a2b7-2dd9419121bd none luks
``` 
This is what the Debian wheezy installer created for me when I created a logical volume named crtest on the volume group mobidisk, and used that for an encrypted root volume. The UUID, by the way, can be found with:
``` 
cryptsetup luksDump /dev/mobidisk/crtest
``` 
Copy the scripts from this repository to their proper place: cryptgnupg_sc in /etc/initramfs-tools/hooks/ and decrypt_gnupg_sc in /lib/cryptsetup/scripts/.

These scripts have been derived from their non-_sc-counterparts.

Have root get your public key. For example:
``` 
gpg --recv-key {YOURKEYID}
``` 
The next step is to create some random material to be used as a LUKS key. I'm simply adapting the instructions from README.gnupg from the cryptsetup package to our use.
 
We create a GnuPG-encrypted file with both a public key and a password, so you can still enter that password when you don't have your smartcard (or your smartcard is broken, and the initramfs demands you insert that specific card, which it will). NOTE that it is only possible to enter a different LUKS password on boot by specifying a custom cryptopts boot argument! By default, only the GnuPG way stays working. That's what the emergency password on the GnuPG-encrypted file is for.

You need to enter both an existing password for the LUKS root volume and a new password for the GnuPG-encrypted file.
``` 
mkdir -m 700 /etc/keys
dd if=/dev/random bs=1 count=256 | gpg -o /etc/keys/cryptkey.gpg -r {YOURKEY} -ec
cd /root
mkfifo -m 700 keyfifo
gpg -d /etc/keys/cryptkey.gpg >keyfifo
``` 

Open a second root terminal and enter:
``` 
cd /root
cryptsetup luksAddKey /dev/mobidisk/crtest keyfifo
``` 

Continue on one of the two terminals (other can be closed):
``` 
rm keyfifo
gpg --export-options export-minimal --export {YOURKEYID} | gpg --no-default-keyring --keyring /etc/keys/pubring.gpg --secret-keyring /etc/keys/secring.gpg --import
gpg --no-default-keyring --keyring /etc/keys/pubring.gpg --secret-keyring /etc/keys/secring.gpg --card-status
``` 
Before you proceed, check if the decryption works on the current system. If this fails, it also will not work after rebooting. You should really fix the problem then before rebooting.

To check the decryption, execute the script in the following way:
``` 
cd /etc/keys
/lib/cryptsetup/scripts/decrypt_gnupg_sc cryptkey.gpg
``` 
If this works, proceed.
 
Adapt /etc/crypttab in the following way (all on one line):
``` 
mobidisk-crtest_crypt UUID=2b0c0898-a92d-48ac-a2b7-2dd9419121bd /etc/keys/cryptkey.gpg luks,keyscript=decrypt_gnupg_sc
``` 

And finally:
``` 
update-initramfs -u
update-initramfs: Generating /boot/initrd.img-4.9.0-3-amd64
WARNING: GnuPG key /etc/keys/crypt_root_volume_key.gpg is copied to initramfs
WARNING: GnuPG secret keyring /etc/keys/secring.gpg is copied to initramfs
WARNING: /usr/bin/gpg is copied to initramfs
WARNING: /usr/bin/gpg-agent is copied to initramfs
WARNING: /usr/lib/gnupg/scdaemon is copied to initramfs
``` 
If your output isn't comparable, look for a mistake.
 
You can now unlock your root volume with your smartcard or the password you entered when you created cryptkey.gpg. If not, you've now locked yourself out of your system. Good luck!

It is possible to have the initramfs ignore your /etc/crypttab (the copy included in the initramfs) by entering a custom cryptopts= boot argument. For instance, if the default command line were:
``` 
BOOT_IMAGE=/vmlinuz-3.13-1-686-pae root=/dev/mapper/mobidisk-crtest_crypt ro initrd=/install/initrd.gz quiet
``` 
You could add:
``` 
cryptopts=target=mobidisk-crtest_crypt,source=/dev/mapper/mobidisk-crtest,luks
``` 

Now you will be prompted for any LUKS password, and decrypt_gnupg_sc is never invoked.
