#!/bin/bash

export PATH=$(pwd)/bin:$(pwd)/bin/apktool:$PATH


BASEROMZIP=$1
PORTROMZIP=$2
VERSION=$3
UPSTREAMURL="https://github.com/OneUI-S20Fe/"

# Function to check if a package is installed
check_packages() {
    for pkg in "$@"; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
            echo "Package $pkg is installed."
        else
            echo "Package $pkg is not installed. Installing $pkg."
            sudo apt update
            sudo apt install "$pkg"
        fi
    done
}



#Function to hopefully auto patch apks

patch_apk() {
    local APKNAME=$1
    local EXTENSION="${APKNAME##*.}"
    local APK_NAME_NO_EXT="${APKNAME%.*}"
    local REPO="${UPSTREAMURL}${APK_NAME_NO_EXT}.${EXTENSION}.git"
    local COMMITHASH=$2
    local LOCALPATH=$(sudo find mounts -type f -iname $APKNAME -printf "%h\n")
    local FULL_PATH="$LOCALPATH/$APKNAME"
    mkdir workingdir
    echo $REPO
    cp $FULL_PATH workingdir/
    cd workingdir
    java -jar ../bin/apktool/apktool.jar d $APKNAME
    cd "${APKNAME}.out"
    git init
    git add *
    git commit -m "initial dummy commit" > /dev/null 2>&1
    git fetch $REPO master
    git cherry-pick -X theirs $COMMITHASH

    java -jar ../../bin/apktool/apktool.jar b
    sudo cp dist/$APKNAME ../../${FULL_PATH}
    cd ../../
    rm -rf workingdir
}

# Function to extract ROM
extract_rom() {
    local ROMZIP=$1
    local DEST_DIR=$2


    local UNPACK_DIR="unpack"
    mkdir -p unpack/ap
    unzip -j "$ROMZIP" "*AP*tar.md5" -d "$UNPACK_DIR"
    mv unpack/AP*.tar.md5 unpack/AP.tar
    tar -xvf $UNPACK_DIR/AP.tar --directory="unpack/ap" --wildcards 'super.img.lz4'
    rm -rf "unpack/AP.tar"
    cd unpack/ap
    lz4 -d super.img.lz4
    simg2img super.img super.raw
    rm -rf super.img
    lpunpack super.raw
    cd -
    mv "unpack"/ap/*.img "$DEST_DIR"
    rm -rf unpack

}

getprop() {
    local stock_file="mounts/vendor_stock/build.prop"
    local port_file="mounts/system/system/build.prop"
    local property=$1
    local device_type=$2
    local file_path=""

    # Set file path based on device type
    if [ "$device_type" == "system" ]; then
        file_path="$port_file"
    elif [ "$device_type" == "vendor" ]; then
        file_path="$stock_file"
    else
        echo "Invalid device type: $device_type"
        return 1
    fi

    # Get the property value
    local value=$(sudo grep "$property" "$file_path" | cut -d '=' -f2)
    echo "$value"
}

replace_props() {
    local OLDTEXT="$2"
    local NEWTEXT="$1"

    echo "OLDTEXT: $OLDTEXT"
    echo "NEWTEXT: $NEWTEXT"
    
    

    sudo find mounts/vendor_stock mounts/system mounts/odm mounts/product -type f -name "*.prop" -exec sed -i "s|$OLDTEXT|$NEWTEXT|g" {} +
}

#check_packages "git" "openjdk-19-jdk" "android-sdk-libsparse-utils" "erofs-utils"

# Extract Base ROM
#extract_rom "$BASEROMZIP" "stock"

# Extract Ported ROM
#extract_rom "$PORTROMZIP" "port"




####################### MOUNTING PART ##########################


#####################################
#detect fs type here
FSTYPE=
######################################

e2fsck -f stock/vendor.img >/dev/null 2>&1

resize2fs stock/vendor.img 2g 2>/dev/null

e2fsck -f port/product.img >/dev/null 2>&1
resize2fs port/product.img 2g 2>/dev/null

e2fsck -f port/system.img 2>/dev/null
resize2fs port/system.img 10g 2>/dev/null

 sudo mount -o rw port/system.img mounts/system 2>/dev/null
 sudo mount -o rw port/vendor.img mounts/vendor 2>/dev/null
 sudo mount -o rw stock/vendor.img mounts/vendor_stock 2>/dev/null
  sudo mount -o rw stock/system.img mounts/system_stock 2>/dev/null
 sudo mount -o rw port/product.img mounts/product 2>/dev/null
 sudo mount -o rw port/odm.img mounts/odm 2>/dev/null

# ############ PATCHING PART ######################################
sudo cp -r patches/fstab.qcom.vendor mounts/vendor_stock/etc/fstab.qcom

#exipatch_apk "services.jar" "9645ea3"


#read target device and port device from build props
TARGET_DEVICE=$(getprop ro.product.vendor.model vendor)
TARGET_NAME=$(getprop ro.product.vendor.name vendor)
PORT_DEVICE=$(getprop ro.product.system.model system)
PORT_NAME=$(getprop ro.product.system.name system)

TARGET_PROPS=($TARGET_DEVICE $TARGET_NAME)
PORT_PROPS=($PORT_DEVICE $PORT_NAME)

# Check if the arrays have the same length
if [ ${#TARGET_PROPS[@]} -ne ${#PORT_PROPS[@]} ]; then
    echo "Error: Arrays have different lengths."
    exit 1
fi

# Loop over the indices of the arrays
for ((i = 0; i < ${#TARGET_PROPS[@]}; i++)); do
    replace_props "${TARGET_PROPS[i]}" "${PORT_PROPS[i]}"
done

#check for vndk30
FILE_TO_CHECK=mounts/system/system/system_ext/apex/com.android.vndk.v30.apex
    # Check if the file exists
    if [ -e "$FILE_TO_CHECK" ]; then
    true
    else
        echo "Error: File $FILE_TO_CHECK not found."
        # Add your logic here for when the file doesn't exist
       # mount stock system and copy file
      sudo cp mounts/system_stock/system/system_ext/apex/com.android.vndk.v30.apex $FILE_TO_CHECK
    fi

sudo rm -rf mounts/system/system/system_ext/etc/selinux

# ########## CREATE EROFS IMAGES ################
# sudo mkfs.erofs -zlz4hc --file-contexts=mounts/system/system/etc/selinux/plat_file_contexts --ignore-mtime system.img mounts/system/
# sudo mkfs.erofs -zlz4hc --ignore-mtime product.img mounts/product/
# sudo mkfs.erofs -zlz4hc --file-contexts=mounts/vendor/etc/selinux/vendor_file_contexts --ignore-mtime vendor.img mounts/vendor/
# sudo mkfs.erofs -zlz4hc --ignore-mtime odm.img mounts/odm/


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
 #sudo umount -f mounts/system
 #sudo umount -f mounts/vendor
 #sudo umount -f mounts/product
 #sudo umount -f mounts/odm

# rm -rf port/*
 #rm -rf stock/*

# rm -rf system.img
# rm -rf product.img
# rm -rf vendor.img
# rm -rf odm.img
rm -rf unpack
# rm -rf updatezip/*.img


 # fi