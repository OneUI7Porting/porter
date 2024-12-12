#!/bin/bash

export PATH=$(pwd)/bin:$(pwd)/bin/apktool:$PATH


BASEROMZIP=$1
PORTROMZIP=$2
UI7UPDATEZIP=$3
VERSION=$4
LOCALPATH=$(pwd)

services_jar_patch_commit_hashes=("8362959" "bc64040")
files_to_remove_vendor=("recovery-from-boot.p" "vendor.samsung.hardware.tlc.iccc@1.0" "vendor.samsung.hardware.tlc.kg" "vaultkeeperd" "vaultkeeper_common" "vendor.samsung.hardware.security.proca@2.0" "vendor.samsung.hardware.security.sem@1.0" "vendor.samsung.hardware.security.hdcp.keyprovisioning@1.0" "android.hardware.cas@1.2" "android.hardware.media.omx@1.0" "android.hardware.camera.provider@2.7-external" "cass")
vendor_cmdline_to_add=("t")

source bin/functions.sh

    if [[ -z "$1" ]]; then
        echo "Usage: gen.sh DeviceFirmwareFile S24OneUI6.1Firmware S24OneUi7UpdateFile RomVersion"
        exit
    fi

check_packages "git" "android-sdk-libsparse-utils" "erofs-utils" "xmlstarlet" "lz4"
mkdir -p port
mkdir -p stock
mkdir -p ui7update
mkdir -p out



# ####################### MOUNTING PART ##########################
# Extract Base ROM
extract_rom "$BASEROMZIP" "stock"

# # Extract Port ROM
 extract_rom "$PORTROMZIP" "port"

# # # Extract OneUI7 Update
unpack_updatezip "ui7update"

# # # Update OneUI6 to 7
updateImage "system" "ui7update" "port"
updateImage "system_ext" "ui7update" "port"
updateImage "product" "ui7update" "port"
updateImage "odm" "ui7update" "port"
updateImage "vendor" "ui7update" "port"

#extract port rom and mount base rom
extract_erofs_images "port" "system.img"
extract_erofs_images "port" "system_ext.img"
extract_erofs_images "port" "odm.img"
extract_erofs_images "port" "product.img"
extract_erofs_images "stock" "vendor.img"

mount_images "stock"

###################################### SYSTEM PATCHING PART ######################################
VNDK_VERSION=$(getprop ro.vndk.version vendor)
replace_selinux "port"
apply_partition_patches "port"
set_device_model "$BASEROMZIP" "floating_feature.xml" "port"

add_line_in_file "port/system" "floating_feature.xml" "<SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS>TRUE</SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS>"

copy_file_to_same_path "stock/system_ext" "com.android.vndk.v$VNDK_VERSION.apex" "port/system_ext"
#patch_apk "services.jar" "${services_jar_patch_commit_hashes[@]}"
replace_props "ro.product.system.model" "stock" "port"
replace_props "ro.product.system.device" "stock" "port"
replace_props "ro.product.system.name" "stock" "port"
replace_props "ro.product.odm.model" "stock" "port"
replace_props "ro.product.odm.device" "stock" "port"
replace_props "ro.product.odm.name" "stock" "port"
replace_props "ro.product.product.model" "stock" "port"
replace_props "ro.product.product.device" "stock" "port"
replace_props "ro.product.product.name" "stock" "port"

edit_floating_feature "patches/floating_feature.txt" "port/system/system/etc"
rm -rf port/system/system/priv-app/CIDManager

###################################### VENDOR PATCHING PART ######################################

rm -rf stock/vendor/lib/*.so stock/vendor/lib/hw stock/vendor/lib/camera stock/vendor/lib/mediadrm stock/vendor/lib/mediacas stock/vendor/lib/rfsa stock/vendor/lib/soundfx stock/vendor/lib/egl stock/vendor/lib/vndk

replace_in_file "stock/vendor" "build.prop" "ro.vendor.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi" "ro.vendor.product.cpu.abilist=arm64-v8a"
replace_in_file "stock/vendor" "build.prop" "ro.vendor.product.cpu.abilist32=armeabi-v7a,armeabi" "ro.vendor.product.cpu.abilist32="
replace_in_file "stock/vendor" "build.prop" "ro.bionic.2nd_arch=arm" "ro.bionic.2nd_arch="
replace_in_file "stock/vendor" "build.prop" "ro.bionic.2nd_cpu_variant=cortex-a75" "ro.bionic.2nd_cpu_variant="
replace_in_file "stock/vendor" "build.prop" "ro.zygote=zygote64_32" "ro.zygote=zygote64"

remove_line_from_file "stock/vendor" "build.prop" "dalvik.vm.isa.arm.variant=cortex-a75"
remove_line_from_file "stock/vendor" "build.prop" "dalvik.vm.isa.arm.features=default"
delete_32bit_elf_files "stock/vendor"
remove_files_by_name "stock/vendor" "${files_to_remove_vendor[@]}"
apply_partition_patches "stock" "vendor"
remove_xml_hal_entry "stock/vendor/etc/vintf/manifest_kalama.xml" #too device specific

###################################### VENDOR BOOT PATCHING PART ######################################
patch_vendor_cmdline "stock/vendor_boot.img" "tmpout" "updatezip/vendor_boot.img" "${vendor_cmdline_to_add[@]}" 
cp stock/boot.img updatezip/
cp patches/init_boot.img updatezip/




# ########## CREATE EROFS IMAGES ################
cd "$LOCALPATH"
mkfs.erofs -zlz4hc --file-contexts=port/system/system/etc/selinux/plat_file_contexts --ignore-mtime ./updatezip/system.img port/system/
mkfs.erofs -zlz4hc --file-contexts=port/system_ext/etc/selinux/system_ext_file_contexts --ignore-mtime ./updatezip/system_ext.img port/system_ext/
mkfs.erofs -zlz4hc --file-contexts=stock/vendor/etc/selinux/vendor_file_contexts --ignore-mtime ./updatezip/vendor.img stock/vendor/
mkfs.erofs -zlz4hc --file-contexts=port/product/etc/selinux/product_file_contexts --ignore-mtime ./updatezip/product.img port/product/
mkfs.erofs -zlz4hc --ignore-mtime ./updatezip/odm.img port/odm/

# ######### CREATE SUPER IMAGE ##################
 bin/lpmake --metadata-size 65536\
  --device-size=12266242048\
  --metadata-slots=2\
  --group=qti_dynamic_partitions:12262047744\
  --partition=system:none:6743986176:qti_dynamic_partitions \
   --partition=odm:none:8683520:qti_dynamic_partitions \
   --partition=product:none:1515485184:qti_dynamic_partitions \
   --partition=system_dlkm:none:3481600:qti_dynamic_partitions \
   --partition=system_ext:none:179703808:qti_dynamic_partitions    \
   --partition=vendor:none:2498473984:qti_dynamic_partitions \
   --partition=vendor_dlkm:none:31961088:qti_dynamic_partitions \
   --output=updatezip/super_empty.img


# ###################### ZIP THE ZIP #############################
rm -rf out/*
zip -r out/CSCSOCROM-DM1Q-$VERSION.zip updatezip/*
# cd ..
#  ################# CLEANUP AND UNMOUNT #######################


#rm -rf port/*
# rm -rf stock/*
rm -rf workingdir

#rm -rf unpack
# rm -rf updatezip/*.img