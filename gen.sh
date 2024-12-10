#!/bin/bash

export PATH=$(pwd)/bin:$(pwd)/bin/apktool:$PATH


BASEROMZIP=$1
PORTROMZIP=$2
UI7UPDATEZIP=$3
VERSION=$4
UPSTREAMURL="https://github.com/OneUI-S23/"

source bin/functions.sh

    if [[ -z "$1" ]]; then
        echo "Usage: gen.sh DeviceFirmwareFile S24OneUI6.1Firmware S24OneUi7UpdateFile RomVersion"
        exit
    fi

check_packages "git" "android-sdk-libsparse-utils" "erofs-utils" "xmlstarlet"


# ####################### MOUNTING PART ##########################
# Extract Base ROM
#extract_rom "$BASEROMZIP" "stock"

# Extract Port ROM
# extract_rom "$PORTROMZIP" "port"

# # Extract OneUI7 Update
# unpack_updatezip "ui7update"

# # Update OneUI6 to 7
# updateImage "system" "ui7update" "port"
# updateImage "system_ext" "ui7update" "port"
# updateImage "product" "ui7update" "port"
# updateImage "odm" "ui7update" "port"
# updateImage "vendor" "ui7update" "port"

#extract port rom and mount base rom
#extract_erofs_images "port"
extract_erofs_images "stock" "vendor.img"

#mount_images "stock"

###################################### SYSTEM PATCHING PART ######################################
#VNDK_VERSION=$(getprop ro.vndk.version vendor)
#replace_selinux "port"
#apply_partition_patches "port"
#replace_in_file "port/system" "floating_feature.xml" "Galaxy S24 Ultra" "Galaxy S23"

#add_line_in_file "port/system" "floating_feature.xml" "<SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS>TRUE</SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS>"

#copy_file_to_same_path "stock/system_ext" "com.android.vndk.v$VNDK_VERSION.apex" "port/system_ext"




###################################### VENDOR PATCHING PART ######################################

rm -rf stock/vendor/lib/*.so stock/vendor/lib/hw stock/vendor/lib/camera stock/vendor/lib/mediadrm stock/vendor/lib/mediacas stock/vendor/lib/rfsa stock/vendor/lib/soundfx stock/vendor/lib/egl stock/vendor/lib/vndk

replace_in_file "stock/vendor" "build.prop" "ro.vendor.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi" "ro.vendor.product.cpu.abilist=arm64-v8a"
replace_in_file "stock/vendor" "build.prop" "ro.vendor.product.cpu.abilist32=armeabi-v7a,armeabi" "ro.vendor.product.cpu.abilist32="
replace_in_file "stock/vendor" "build.prop" "ro.bionic.2nd_arch=arm" "ro.bionic.2nd_arch="
replace_in_file "stock/vendor" "build.prop" "ro.bionic.2nd_cpu_variant=cortex-a75" "ro.bionic.2nd_cpu_variant="
replace_in_file "stock/vendor" "build.prop" "ro.zygote=zygote64_32" "ro.zygote=zygote64"

remove_line_from_file "stock/vendor" "build.prop" "dalvik.vm.isa.arm.variant=cortex-a75"
remove_line_from_file "stock/vendor" "build.prop" "dalvik.vm.isa.arm.features=default"
files_to_remove=("recovery-from-boot.p" "vendor.samsung.hardware.tlc.iccc@1.0" "vendor.samsung.hardware.tlc.kg" "vaultkeeperd" "vaultkeeper_common" "vendor.samsung.hardware.security.proca@2.0" "vendor.samsung.hardware.security.sem@1.0" "vendor.samsung.hardware.security.hdcp.keyprovisioning@1.0" "android.hardware.cas@1.2" "android.hardware.media.omx@1.0" "android.hardware.camera.provider@2.7-external" "cass")
delete_32bit_elf_files "stock/vendor"
remove_files_by_name "stock/vendor" "${files_to_remove[@]}"
apply_partition_patches "stock" "vendor"
remove_xml_hal_entry "stock/vendor/etc/vintf/manifest_kalama.xml"

###################################### VENDOR BOOT PATCHING PART ######################################




# #read target device and port device from build props
# TARGET_DEVICE=$(getprop ro.product.vendor.model vendor)
# TARGET_NAME=$(getprop ro.product.vendor.name vendor)
# PORT_DEVICE=$(getprop ro.product.system.model system)
# PORT_NAME=$(getprop ro.product.system.name system)
# TARGET_QB_ID=$(getprop ro.system.qb.id system_stock)
# PORT_QB_ID=$(getprop ro.system.qb.id system)
# TARGET_FINGEPRINT=$(getprop ro.system.build.fingerprint system_stock)
# PORT_FINGEPRINT=$(getprop ro.system.build.fingerprint system)
# TARGET_INCREMENTAL=$(getprop ro.system.build.version.incremental system_stock)
# PORT_INCREMENTAL=$(getprop ro.system.build.version.incremental system)
# TARGET_DISPLAY_ID=$(getprop ro.build.display.id system_stock)
# PORT_DISPLAY_ID=$(getprop ro.build.display.id system)
# TARGET_DESCRIPTION=$(getorop ro.build.description system_stock)
# PORT_DESCRIPTION=$(getorop ro.build.description system)
# TARGET_CHANGELIST=$(getprop ro.build.changelist system_stock)
# PORT_CHANGELIST=$(getprop ro.build.changelist system)
# VNDK_VERSION=$(getprop ro.vndk.version vendor)

# TARGET_PROPS=($TARGET_DEVICE $TARGET_NAME $TARGET_QB_ID $TARGET_FINGEPRINT $TARGET_INCREMENTAL $TARGET_DISPLAY_ID $TARGET_DESCRIPTION $TARGET_CHANGELIST)
# PORT_PROPS=($PORT_DEVICE $PORT_NAME $PORT_QB_ID $PORT_FINGEPRINT $PORT_INCREMENTAL $PORT_DISPLAY_ID $PORT_DESCRIPTION $PORT_CHANGELIST)

# # Check if the arrays have the same length
# if [ ${#TARGET_PROPS[@]} -ne ${#PORT_PROPS[@]} ]; then
#     echo "Error: Arrays have different lengths."
#     exit 1
# fi
# echo "replacing props"
# # Loop over the indices of the arrays
# for ((i = 0; i < ${#TARGET_PROPS[@]}; i++)); do
#     replace_props "${TARGET_PROPS[i]}" "${PORT_PROPS[i]}"
# done

# ########## CREATE EROFS IMAGES ################
# mkfs.erofs -zlz4hc --file-contexts=port/system/system/etc/selinux/plat_file_contexts --ignore-mtime ./out/system.img port/system/
# mkfs.erofs -zlz4hc --file-contexts=port/system_ext/etc/selinux/system_ext_file_contexts --ignore-mtime ./out/system_ext.img port/system_ext/
mkfs.erofs -zlz4hc --file-contexts=stock/vendor/etc/selinux/vendor_file_contexts --ignore-mtime ./out/vendor.img stock/vendor/
# mkfs.erofs -zlz4hc --file-contexts=port/product/etc/selinux/product_file_contexts --ignore-mtime ../out/product.img port/product/
# mkfs.erofs -zlz4hc --file-contexts=port/odm/etc/selinux/odm_file_contexts --ignore-mtime ./out/odm.img port/odm/

# ######### CREATE SUPER IMAGE ##################
# lpmake --metadata-size 65536\
#  --device-size=10292822016\
#  --metadata-slots=2\
#  --group=qti_dynamic_partitions:10288627712\
#  --partition=system:none:4364660736:qti_dynamic_partitions\
#  --partition=vendor:none:1992294400:qti_dynamic_partitions\
#  --partition=product:none:565809152:qti_dynamic_partitions\
#  --partition=odm:none:4349952:qti_dynamic_partitions\
#  --image=odm=./odm.img\
#  --image=product=./product.img\
#  --image=system=./system.img\
#  --image=vendor=./vendor.img\
#  --output ./super.img

# ################ COPY TOGETHER INSTALLER ZIP ################
# mv super.img updatezip/
# cp rom/boot.img updatezip/


# ###################### ZIP THE ZIP #############################
# cd updatezip
# zip -r ../SealRom-R8Q-$VERSION.zip *
# cd ..
#  ################# CLEANUP AND UNMOUNT #######################


# rm -rf port/*
 #rm -rf stock/*

# rm -rf system.img
# rm -rf product.img
# rm -rf vendor.img
# rm -rf odm.img
#rm -rf unpack
# rm -rf updatezip/*.img


 # fi