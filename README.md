# gpg-encrypted-root
Encrypt your root volume with an OpenPGP smartcard

This repository is based on the software and information from [this tutorial](http://digitalbrains.com/2014/gpgcryptroot) by Peter Lebbing.

## Old tutorial by Peter Lebbing

> Things have sure come along since I wrote 
> <http://digitalbrains.com/2014/gpgcryptroot.tar.gz>. We can now use GnuPG
> properly from an initramfs in Debian jessie. Unfortunately, the supplied scripts
> only handle the case where GnuPG is used with symmetric (password based)
> encryption. I'm not sure in which circumstances you would want to use that;
> smartcard based decryption is so much cooler than that!
> 
> This mini-guide is for advanced users; I assume you understand all the commands
> involved. I recommend reading the scripts to see what they are like.
> 
> Let's assume you used LUKS to put a password on your root volume, for instance
> by using the Debian installer. We will install a LUKS "password" that is
> unlocked by an OpenPGP smartcard.
>  
> (If you also have other volumes protected by LUKS and want to unlock those with
> your smartcard, see the section "Decrypt derived" further down.)
> 
> So suppose your /etc/crypttab looks something like this:
> 
> ------------------------------8<---------------->8------------------------------
> mobidisk-crtest_crypt UUID=2b0c0898-a92d-48ac-a2b7-2dd9419121bd none luks
> ------------------------------8<---------------->8------------------------------
> 
> This is what the Debian wheezy installer created for me when I created a logical
> volume named crtest on the volume group mobidisk, and used that for an encrypted
> root volume. The UUID, by the way, can be found with:
> 
> # cryptsetup luksDump /dev/mobidisk/crtest
> 
> Copy the included scripts to their proper place: cryptgnupg_sc in
> /etc/initramfs-tools/hooks/ and decrypt_gnupg_sc in /lib/cryptsetup/scripts/.
> These scripts have been derived from their non-_sc-counterparts.
> 
> Have root get your public key. For example:
> 
> # gpg --recv-key {YOURKEYID}
> 
> The next step is to create some random material to be used as a LUKS key. I'm
> simply adapting the instructions from README.gnupg from the cryptsetup package
> to our use.
> 
> We create a GnuPG-encrypted file with both a public key and a password, so you
> can still enter that password when you don't have your smartcard (or your
> smartcard is broken, and the initramfs demands you insert that specific card,
> which it will). NOTE that it is only possible to enter a different LUKS password
> on boot by specifying a custom cryptopts boot argument! By default, only the
> GnuPG way stays working. That's what the emergency password on the
> GnuPG-encrypted file is for.
> 
> You need to enter both an existing password for the LUKS root volume and a new
> password for the GnuPG-encrypted file.
> 
> # mkdir -m 700 /etc/keys
> # dd if=/dev/random bs=1 count=256 | gpg -o /etc/keys/cryptkey.gpg \
> 	-r {YOURKEY} -ec
> # cd /root
> # mkfifo -m 700 keyfifo
> # gpg -d /etc/keys/cryptkey.gpg >keyfifo
> 
> Open a second root terminal and enter:
> 
> # cd /root
> # cryptsetup luksAddKey /dev/mobidisk/crtest keyfifo
> 
> Continue on one of the two terminals (other can be closed):
> 
> # rm keyfifo
> # gpg --export-options export-minimal --export {YOURKEYID} | gpg \
> 	--no-default-keyring --keyring /etc/keys/pubring.gpg --secret-keyring \
> 	/etc/keys/secring.gpg --import
> # gpg --no-default-keyring --keyring /etc/keys/pubring.gpg --secret-keyring \
> 	/etc/keys/secring.gpg --card-status
> 
> Adapt /etc/crypttab in the following way (all on one line):
> 
> ------------------------------8<---------------->8------------------------------
> mobidisk-crtest_crypt UUID=2b0c0898-a92d-48ac-a2b7-2dd9419121bd
> /etc/keys/cryptkey.gpg luks,keyscript=decrypt_gnupg_sc
> ------------------------------8<---------------->8------------------------------
> 
> And finally:
> 
> # update-initramfs -u
> update-initramfs: Generating /boot/initrd.img-3.13-1-686-pae
> WARNING: GnuPG key /etc/keys/cryptkey-new.gpg is copied to initramfs
> WARNING: GnuPG secret keyring /etc/keys/secring.gpg is copied to initramfs
> 
> If your output isn't comparable, look for a mistake.
> 
> You can now unlock your root volume with your smartcard or the password you
> entered when you created cryptkey.gpg. If not, you've now locked yourself out of
> your system. Good luck!
> 
> It is possible to have the initramfs ignore your /etc/crypttab (the copy
> included in the initramfs) by entering a custom cryptopts= boot argument. For
> instance, if the default command line were:
> 
> BOOT_IMAGE=/vmlinuz-3.13-1-686-pae root=/dev/mapper/mobidisk-crtest_crypt ro initrd=/install/initrd.gz quiet
> 
> You could add:
> 
> cryptopts=target=mobidisk-crtest_crypt,source=/dev/mapper/mobidisk-crtest,luks
> 
> Now you will be prompted for any LUKS password, and decrypt_gnupg_sc is never invoked.
> 
> Decrypt derived
> ---------------
> 
> README.initramfs in the cryptsetup package discusses the "decrypt_derived"
> script, but it only uses this to unlock a plain dm-crypt volume, not a LUKS
> volume. If you used the Debian installer to create multiple LUKS volumes, it
> would be nice if they were all unlocked on boot without having to enter the
> smartcard PIN multiple times. "decrypt_derived" takes the master key from an
> already unlocked volume (that is, the cryptographic key actually used to encrypt
> data on the volume, not one of the LUKS passwords), and uses that as key for the
> volume to unlock. With LUKS, it's possible to use the master key as a LUKS
> "password".
> 
> I'm assuming the /etc/crypttab is as follows:
> 
> ------------------------------8<---------------->8------------------------------
> mobidisk-crtest_crypt [...]
> mobidisk-crdata_crypt UUID=2fa1fd9d-e169-4d55-a59e-a0bd0553444f none luks
> ------------------------------8<---------------->8------------------------------
> 
> Enter the following command. You will be prompted for an existing LUKS password
> for crdata.
> 
> # cryptsetup luksAddKey /dev/mobidisk/crdata \
> 	<(/lib/cryptsetup/scripts/decrypt_derived mobidisk-crtest_crypt)
> 
> Change /etc/crypttab to:
> 
> ------------------------------8<---------------->8------------------------------
> mobidisk-crtest_crypt [...]
> mobidisk-crdata_crypt UUID=2fa1fd9d-e169-4d55-a59e-a0bd0553444f \
> 	mobidisk-crtest_crypt luks,keyscript=decrypt_derived
> ------------------------------8<---------------->8------------------------------
> 
> The entry for crdata is one line; escape-style continuation is not supported for
> crypttab, and only used here for readability.
> 
