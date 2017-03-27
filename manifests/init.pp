# This module manages the enabling and disabling of FIPS on a system
# It will set the kernel boot parametes and install/remove the dracut packages
# and rebuild initramfs images.
#
# Changing the FIPS status of a system changes the cryptographic modules used.
# This can affect existing keys and certificates and make them unusable.  Make
# sure these affect are understood before changing the status.
#
# @param enabled
#   If FIPS should be enable or disabled on the system.
#
# @param aesni
#   NOTE: This parameter is controlled by params.pp
#   This parameter indicates wether or not the system uses the
#   Advanced Encryption Standard New Instructions set.
#
class fips (
  Boolean $enabled = simplib::lookup('simp_options::fips', { 'default_value' => true }),
  Boolean $aesni   = $::fips::params::aesni
) inherits fips::params {

  case $facts['os']['family'] {

    'RedHat': {

      $fips_kernel_value = $enabled ? {
        true    => '1',
        default => '0'
      }

      # The dracut packages need to removed/added and the image rebuilt
      # depending on fips status or the system won't boot properly.
      $fips_package_status = $enabled ? {
        true    => 'latest',
        default => 'absent'
      }

      kernel_parameter {
        'fips':
          value  => $fips_kernel_value,
          notify => Reboot_notify['fips'];
          # bootmode => 'normal', # This doesn't work due to a bug in the Grub Augeas Provider
        'boot':
          value  => "UUID=${::boot_dir_uuid}",
          notify => Reboot_notify['fips'];
          # bootmode => 'normal', # This doesn't work due to a bug in the Grub Augeas Provider
      }

      package {
        'dracut-fips':
          ensure => $fips_package_status,
          notify => Exec['dracut_rebuild'];
        'fipscheck':
          ensure => latest
      }

      if $aesni {
        package { 'dracut-fips-aesni':
          ensure => $fips_package_status,
          notify => Exec['dracut_rebuild']
        }
        # There were failures if the packages are not removed/installed in the correct
        # order
        if $enabled {
          Package['dracut-fips'] -> Package['dracut-fips-aesni']
        } else {
          Package['dracut-fips-aesni'] -> Package['dracut-fips']
        }
      }

      reboot_notify { 'fips': }

      # If the NSS and dracut packages don't stay reasonably in sync, your system
      # may not reboot.
      package { 'nss': ensure => 'latest' }

      exec { 'dracut_rebuild':
        command     => '/sbin/dracut -f',
        subscribe   => Package['nss'],
        refreshonly => true
      }
    }
    default : {
      fail('Only the RedHat family is supported by the simp fips module at this time.')
    }
  }
}
