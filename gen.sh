#!/bin/bash

export PATH=$(pwd)/bin:$(pwd)/bin/apktool:$PATH


BASEROMZIP=$1
PORTROMZIP=$2
UI7UPDATEZIP=$3
BETA2ZIP=$4
BETA3ZIP=$5
VERSION=$6
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



####################### MOUNTING PART ##########################
#Extract Base ROM
extract_rom "$BASEROMZIP" "stock"

#Extract Port ROM
extract_rom "$PORTROMZIP" "port"

#Extract OneUI7 Update
unpack_updatezip "ui7update"

#Update OneUI6 to 7
updateImage "system" "ui7update" "port"
updateImage "system_ext" "ui7update" "port"
updateImage "product" "ui7update" "port"
updateImage "odm" "ui7update" "port"
updateImage "vendor" "ui7update" "port"

#Extract OneUI7 Update 2
UI7UPDATEZIP = BETA2ZIP
unpack_updatezip "ui7update"

#Update OneUI6 to 7
updateImage "system" "ui7update" "port"
updateImage "system_ext" "ui7update" "port"
updateImage "product" "ui7update" "port"
updateImage "odm" "ui7update" "port"
updateImage "vendor" "ui7update" "port"

#Extract OneUI7 Update 3
UI7UPDATEZIP = BETA3ZIP
unpack_updatezip "ui7update"

#Update OneUI6 to 7
updateImage "system" "ui7update" "port"
updateImage "system_ext" "ui7update" "port"
updateImage "product" "ui7update" "port"
updateImage "odm" "ui7update" "port"
updateImage "vendor" "ui7update" "port"

#Extract port rom and mount base rom
extract_erofs_images "port" "system.img"
 extract_erofs_images "port" "system_ext.img"
 extract_erofs_images "port" "odm.img"
 extract_erofs_images "port" "product.img"
 extract_erofs_images "stock" "vendor.img"

mount_images "stock"

###################################### SYSTEM PATCHING PART ######################################
VNDK_VERSION=$(getprop ro.vndk.version vendor)
DEVICE_MODEL=$(getprop ro.product.vendor.model vendor)
replace_selinux "port"
rm -rf port/system/system/etc/vintf
apply_partition_patches "port"
echo $DEVICE_MODEL
set_device_model "$DEVICE_MODEL" "floating_feature.xml" "port/system"

add_line_in_file "port/system" "floating_feature.xml" "<SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS>TRUE</SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS>"

copy_file_to_same_path "stock/system_ext" "com.android.vndk.v$VNDK_VERSION.apex" "port/system_ext"
#copy_file_to_same_path "stock/system/system" "camera-feature.xml" "port/system/system"
#patch_apk "services.jar" "${services_jar_patch_commit_hashes[@]}"
replace_props "ro.product.system.model" "stock/system/system" "port/system/system"
replace_props "ro.product.system.device" "stock/system/system" "port/system/system"
replace_props "ro.product.system.name" "stock/system/system" "port/system/system"
replace_props "ro.product.odm.model" "stock/odm" "port/odm"
replace_props "ro.product.odm.device" "stock/odm" "port/odm"
replace_props "ro.product.odm.name" "stock/odm" "port/odm"
replace_props "ro.product.product.model" "stock/product" "port/product"
replace_props "ro.product.product.device" "stock/product" "port/product"
replace_props "ro.product.product.name" "stock/product" "port/product"

replace_props "ro.system.build.fingerprint" "stock/system/system" "port/system/system"
replace_props "ro.system.build.id" "stock/system/system" "port/system/system"
replace_props "ro.system_ext.build.id" "stock/system_ext" "port/system_ext"
replace_props "ro.system_ext.build.fingerprint" "stock/system_ext" "port/system_ext"
replace_props "ro.product.build.id" "stock/product" "port/product"
replace_props "ro.product.build.fingerprint" "stock/product" "port/product"
replace_props "ro.odm.build.id" "stock/odm" "port/odm"
replace_props "ro.odm.build.fingerprint" "stock/odm" "port/odm"

replace_props "ro.build.official.release" "stock" "port" "false"
replace_props "ro.build.official.developer" "stock" "port" "true"

edit_floating_feature "patches/floating_feature.txt" "port/system/system/etc"

#Remove annoying popups
rm -rf port/system/system/priv-app/CIDManager
rm -rf port/system/system/priv-app/GalaxyBetaService

#Remove any trace of FuckerBerg if present
rm -rf port/system/system/priv-app/FBInstaller_NS
rm -rf port/system/system/app/FBAppManager_NS
rm -rf port/system/system/priv-app/FBServices
rm -rf port/system/system/preload/Facebook_stub_preload

#Camera app ?
rm -rf patches/libsusedbycamera.txt
extract_apk_libs "SamsungCamera.apk" "port/system/system/priv-app/" "patches/libsusedbycamera.txt"
copy_file_to_same_path "stock/system/system" "vendor.samsung.hardware.snap-V2-ndk.so" "port/system/system"

copy_files_from_list "stock/system" "port/system" "public.libraries-camera.samsung.txt"
copy_files_from_list "stock/system" "port/system" "public.libraries-arcsoft.txt"
copy_files_from_list "stock/system" "port/system" "patches/libsusedbycamera.txt" "true"

#Dolby Atmos
copy_file_to_same_path "stock/system/system" "libswdap_legacy.so" "port/system/system"
copy_file_to_same_path "stock/system/system" "libswspatializer_legacy.so" "port/system/system"
copy_file_to_same_path "stock/system/system/etc" "audio_effects.xml" "port/system/system/etc"
copy_file_to_same_path "stock/system/system/etc" "audio_effects_common.conf" "port/system/system/etc"

###################################### PRODUCT PATCHING PART ######################################
files_to_remove_product=("HotwordEnrollmentXGoogleEx4HEXAGON.apk" "HotwordEnrollmentOKGoogleEx4HEXAGON.apk" "framework-res__e3qxxx__auto_generated_rro_product.apk" "framework-res__phone__auto_generated_characteristics_rro.apk")
remove_files_by_name "port/product" "${files_to_remove_product[@]}"
copy_file_to_same_path "stock/product/overlay" "framework-res__auto_generated_rro_product.apk" "port/product/overlay"

copy_file_to_same_path "stock/product/priv-app" "HotwordEnrollmentOKGoogleEx4HEXAGON.apk" "port/product/priv-app"
copy_file_to_same_path "stock/product/priv-app" "HotwordEnrollmentXGoogleEx4HEXAGON.apk" "port/product/priv-app"


###################################### SYSTEM_EXT PATCHING PART ######################################
copy_file_to_same_path "stock/system_ext" "libpenguin.so" "port/system_ext"
copy_file_to_same_path "stock/system_ext" "libpenguin_impl.so" "port/system_ext"



###################################### VENDOR PATCHING PART ######################################

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

copy_file_to_same_path "port/vendor" "vendor.samsung.hardware.snap-V2-ndk.so" "stock/vendor"
copy_file_to_same_path "port/vendor" "libvui_dmgr_client.so" "stock/vendor"
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
#  bin/lpmake --metadata-size 65536\
#   --device-size=12266242048\
#   --metadata-slots=2\
#   --group=qti_dynamic_partitions:12262047744\
#   --partition=system:none:6743986176:qti_dynamic_partitions \
#    --partition=odm:none:8683520:qti_dynamic_partitions \
#    --partition=product:none:1515485184:qti_dynamic_partitions \
#    --partition=system_dlkm:none:3481600:qti_dynamic_partitions \
#    --partition=system_ext:none:179703808:qti_dynamic_partitions    \
#    --partition=vendor:none:2498473984:qti_dynamic_partitions \
#    --partition=vendor_dlkm:none:31961088:qti_dynamic_partitions \
#    --output=updatezip/super_empty.img


# # ###################### ZIP THE ZIP #############################
# rm -rf out/*
# cd updatezip
# zip -r ../out/CSCSOCROM-DM1Q-$VERSION.zip updatezip/*
# cd ..
#  ################# CLEANUP AND UNMOUNT #######################


#rm -rf port/*
# rm -rf stock/*
rm -rf workingdir

#rm -rf unpack
# rm -rf updatezip/*.img
