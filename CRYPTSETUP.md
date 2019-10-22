# Using cryptsetup for root volume smartcard decryption
In the meantime, smartcard decryption for the root volume is supported by cryptsetup directly. This document describes how to setup your system for root volume decryption at bootup using your smartcard.

The corresponding documentation of the cryptsetup feature can be found [here](https://cryptsetup-team.pages.debian.net/cryptsetup/README.gnupg-sc.html). Anyhow, it describes the general feature and not the complete use case of decrypting a root volume at bootup using a smartcard.

I assume that you created an encrypted root volume using the debian installer. This tutorial is about adding the possibility to also decrypt the root volume with a smartcard.

We follow the tutorial linked above with some modifications and extra steps. First, we create an encryption key exactly as stated in the tutorial:
```
dd if=/dev/random bs=1 count=256 | gpg --recipient DEADBEEF --output /etc/keys/cryptkey.gpg --encrypt
```

Make sure to replace "DEADBEEF" by your GPG key's fingerprint.

Next, we will add the key for device decryption of our root volume. We will do this with different commands than in the tutorial (/dev/vda5 is my encrypted root volume, you might need to replace it with yours):
```
cd /root
mkfifo -m 700 keyfifo
/lib/cryptsetup/scripts/decrypt_gnupg-sc /etc/keys/cryptkey.gpg >keyfifo
```

Open a second root terminal and enter:
```
cd /root
cryptsetup luksAddKey /dev/vda5 keyfifo
rm keyfifo
```

You will be asked to enter an existing password for the LUKS container by the `cryptsetup` line above.

The next step is to alter the file /etc/crypttab. Since the debian installer should have created it, I suppose it looks something like this:
```
vda5_crypt UUID=37b9967a-f696-4f4d-802b-96c2ab1d92c5 none luks,discard
```

We now change it to look like this:
```
vda5_crypt UUID=37b9967a-f696-4f4d-802b-96c2ab1d92c5 /etc/keys/cryptkey.gpg luks,keyscript=decrypt_gnupg-sc
```

So we changed everything behind the UUID to enable smartcard decryption with the key we created.

The next step is to export our public keyring to the directory where cryptsetup will pick it up to include it in the initramfs:
```
gpg --export DEADBEEF >/etc/cryptsetup-initramfs/pubring.gpg
```

Again, make sure to replace "DEADBEEF" with your key's fingerprint.

Finally, we update our initramfs:
```
update-initramfs -u
```

That's it! When you reboot, you should be prompted for your smartcard PIN. After entering it, the root volume is decrypted and your system is booted. If not, probably something went wrong and you locked yourself out of the system.
