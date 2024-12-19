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

UPSTREAMURL="https://github.com/OneUI7Porting/"

#Function to hopefully auto patch apks

patch_apk() {
    local APKNAME=$1
    shift
    local COMMIT_HASHES=($@)

    if [[ -z "$APKNAME" || ${#COMMIT_HASHES[@]} -eq 0 ]]; then
        echo "Usage: patch_apk <APKNAME> <COMMIT_HASH_1> [<COMMIT_HASH_2> ...]"
        return 1
    fi

    local EXTENSION="${APKNAME##*.}"
    local APK_NAME_NO_EXT="${APKNAME%.*}"
    local REPO="${UPSTREAMURL}${APK_NAME_NO_EXT}.${EXTENSION}.git"

    # Find the local path of the APK
    local LOCALPATH=$(sudo find port -type f -iname "$APKNAME" -printf "%h\n")
    if [[ -z "$LOCALPATH" ]]; then
        echo "Error: APK not found in 'port' directory"
        return 1
    fi

    local FULL_PATH="$LOCALPATH/$APKNAME"

    # Create a working directory
    mkdir -p workingdir

    echo "Cloning repository: $REPO"
    cp "$FULL_PATH" workingdir/

    cd workingdir || return 1

    # Decompile the APK
    if ! java -jar ../bin/apktool/apktool_2.10.0.jar d "$APKNAME"; then
        echo "Error: Failed to decompile APK"
        cd ..
        return 1
    fi

    cd "${APKNAME}.out" || return 1

    # Initialize a git repository and apply the patches
    git init > /dev/null
    git add .
    git commit -m "Initial dummy commit" > /dev/null 2>&1

    if ! git fetch "$REPO" master; then
        echo "Error: Failed to fetch from repository"
        cd ../../
        return 1
    fi

    for COMMITHASH in "${COMMIT_HASHES[@]}"; do
        if ! git cherry-pick -X theirs "$COMMITHASH"; then
            echo "Error: Cherry-pick failed for commit $COMMITHASH"
            cd ../../
            return 1
        fi
    done

    # Rebuild the APK
    if ! java -jar ../../bin/apktool/apktool_2.10.0.jar b; then
        echo "Error: Failed to rebuild APK"
        cd ../../
        return 1
    fi
    pwd
    # Uncomment the following lines to copy the rebuilt APK back to the original location
    cp "dist/$APKNAME" "../../$FULL_PATH"

    cd ../../

    echo "APK patched and rebuilt successfully."
}

# Function to extract ROM
extract_rom() {
    local ROMZIP=$1
    local DEST_DIR=$2

    local UNPACK_DIR="unpack"
    mkdir -p $UNPACK_DIR/ap
    unzip -j "$ROMZIP" "*AP*tar.md5" -d "$UNPACK_DIR"
    mv $UNPACK_DIR/AP*.tar.md5 $UNPACK_DIR/AP.tar

    if [ "$DEST_DIR" == "stock" ]; then
        # Extract the wildcarded images if DEST_DIR is "stock"
        tar -xvf $UNPACK_DIR/AP.tar --directory="$UNPACK_DIR/ap" --wildcards 'super.img.lz4' 'vendor_boot.img.lz4' 'boot.img.lz4'
        
        # Extract only the new lz4 files (vendor_boot.img.lz4 and boot.img.lz4)
        if [ -f "$UNPACK_DIR/ap/vendor_boot.img.lz4" ]; then
            lz4 -d "$UNPACK_DIR/ap/vendor_boot.img.lz4"
            rm -rf "$UNPACK_DIR/ap/vendor_boot.img.lz4"
        fi
        if [ -f "$UNPACK_DIR/ap/boot.img.lz4" ]; then
            lz4 -d "$UNPACK_DIR/ap/boot.img.lz4"
            rm -rf "$UNPACK_DIR/ap/boot.img.lz4"
        fi
    else
        # Extract only super.img.lz4 if DEST_DIR is not "stock"
        tar -xvf $UNPACK_DIR/AP.tar --directory="$UNPACK_DIR/ap" --wildcards 'super.img.lz4'
    fi

    rm -rf "$UNPACK_DIR/AP.tar"

    cd $UNPACK_DIR/ap
    # Decompress the super.img.lz4 if it exists
    if [ -f "super.img.lz4" ]; then
        lz4 -d super.img.lz4
        rm -rf super.img.lz4
    fi

    simg2img super.img super.raw
    rm -rf super.img
    "$LOCALPATH"/bin/lpunpack -p system -p system_ext -p product -p odm -p vendor -p system_dlkm -p vendor_dlkm super.raw
    rm -rf super.raw
    cd -

    # Move the extracted .img files to the destination directory
    mv $UNPACK_DIR/ap/*.img "$DEST_DIR"

    rm -rf unpack
}



updateImage() {
    # Check if a partition name is provided
    if [[ -z "$1" ]]; then
        echo "Usage: updateImage <partition_name>"
        return 1
    fi

    # Define variables based on the partition name
    local partition_name="$1"
    local ui7_update_path="$2"
    local ui6_base_path="$3"
    local transfer_list="${ui7_update_path}/${partition_name}.transfer.list"
    local new_dat="${ui7_update_path}/${partition_name}.new.dat"
    local patch_dat="${ui7_update_path}/${partition_name}.patch.dat"
    local img_file="${ui6_base_path}/${partition_name}.img"

    # Construct the command
    local cmd="BlockImageUpdate $img_file $transfer_list $new_dat $patch_dat"

    # Execute the command
    echo "Executing: $cmd"
    eval "$cmd"
    rm -rf cache
}

getprop() {
    local property=$1
    local partition_type=$2
    local stock_file="stock/vendor/build.prop"
    local port_file="port/system/system/build.prop"
    local system_stock_file="stock/system/system/build.prop"
    local file_path=""

    if [ "$partition_type" == "system" ]; then
        file_path="$port_file"
    elif [ "$partition_type" == "vendor" ]; then
        file_path="$stock_file"
    elif [ "$partition_type" == "system_stock" ]; then
        file_path="$system_stock_file"
    else
        echo "Invalid device type: $partition_type"
        return 1
    fi

    # Get the property value
    local value=$(sudo grep "$property" "$file_path" | cut -d '=' -f2)
    
    # Return the value
    echo "$value"
}

replace_props() {
    local PROP="$1"
    local NEW_DIRECTORY="$2"
    local DIRECTORY="$3"
    local NEW_VALUE_OVERRIDE="$4"

    if [[ -n "$NEW_VALUE_OVERRIDE" ]]; then
        echo "Using supplied new value for property: $PROP"
        local NEW_VALUE="$NEW_VALUE_OVERRIDE"
    else
        echo "Searching for new value for property: $PROP in $NEW_DIRECTORY"
        local NEW_VALUE=$(sudo grep --exclude=*.img -r "^$PROP=" "$NEW_DIRECTORY" | head -n 1 | cut -d'=' -f2)

        if [[ -z "$NEW_VALUE" ]]; then
            echo "Error: New value for $PROP not found in $NEW_DIRECTORY"
            return 1
        fi
    fi

    echo "Replacing $PROP with new value: $NEW_VALUE in $DIRECTORY"

    find "$DIRECTORY" -type f -name "*.prop" -exec sed -i "s|^$PROP=.*|$PROP=$NEW_VALUE|g" {} +

    echo "Property $PROP updated successfully in $DIRECTORY."
}



unpack_updatezip() {
    if [[ -z "$1" ]]; then
        echo "Usage: unpack_updatezip <extractdir>"
        return 1
    fi
    local extractdir="$1"
    if [[ ! -d "$extractdir" ]]; then
        echo "Directory '$extractdir' does not exist. Creating it..."
        mkdir -p "$extractdir"
    fi

    # Unzip the file into the specified directory
    unzip -j "$UI7UPDATEZIP" -d "$extractdir"
}

apply_partition_patches() {
    # Define source and destination base paths
    patches_dir="patches"
    portrom_dir="$1"

    # Define the list of valid partition names
    valid_partitions=("system" "system_ext" "product" "odm")

    # Handle the vendor directory if the third parameter is set to true
    vendor_patch=false
    if [ "$2" == "vendor" ]; then
        vendor_patch=true
    fi

    # If the vendor flag is set, skip all partitions except vendor
    if [ "$vendor_patch" == true ]; then
        # Only copy vendor patches and skip others
        vendor_source_path="$patches_dir/vendor"
        
        # Check if the vendor folder exists in the patches directory
        if [ -d "$vendor_source_path" ]; then
            vendor_target_path="$portrom_dir/vendor"

            # Create the target vendor folder if it doesn't exist
            mkdir -p "$vendor_target_path"

            # Copy contents with forced overwrite
            echo "Copying contents of $vendor_source_path to $vendor_target_path..."
            cp -rf "$vendor_source_path/"* "$vendor_target_path/"

            # Check success
            if [ $? -eq 0 ]; then
                echo "Successfully applied vendor patches."
            else
                echo "Failed to apply vendor patches. Check permissions and paths."
            fi
        else
            echo "No vendor patches found in $patches_dir. Skipping vendor."
        fi

        # Skip the rest of the partitions
        return
    fi

    # Iterate through the valid partitions and apply patches to each one
    for partition in "${valid_partitions[@]}"; do
        source_path="$patches_dir/$partition"

        # Check if the source folder exists and is a directory
        if [ -d "$source_path" ]; then
            target_path="$portrom_dir/$partition"

            # Create the target partition folder if it doesn't exist
            mkdir -p "$target_path"

            # Copy contents with forced overwrite
            echo "Copying contents of $source_path to $target_path..."
            cp -rf "$source_path/"* "$target_path/"

            # Check success
            if [ $? -eq 0 ]; then
                echo "Successfully applied patches to $partition."
            else
                echo "Failed to apply patches to $partition. Check permissions and paths."
            fi
        else
            echo "No patches found for $partition in $patches_dir. Skipping..."
        fi
    done
}




replace_in_file() {
    # Parameters
    search_folder="$1"   # Folder to search in
    filename="$2"        # Name of the file to find
    search_value="$3"    # Value to look for in the file
    replacement_value="$4" # Value to replace with

    # Check if the search folder exists
    if [ ! -d "$search_folder" ]; then
        echo "Error: Directory $search_folder does not exist."
        return 1
    fi

    # Find the file in the directory and its subdirectories
    file_path=$(find "$search_folder" -type f -name "$filename" | head -n 1)

    # Check if the file was found
    if [ -z "$file_path" ]; then
        echo "Error: File $filename not found in $search_folder."
        return 1
    fi

    # Perform the replacement in the found file
    echo "Found $filename at $file_path. Replacing '$search_value' with '$replacement_value'..."
    sed -i "s/$search_value/$replacement_value/g" "$file_path"

    # Check if the replacement was successful
    if [ $? -eq 0 ]; then
        echo "Successfully replaced '$search_value' with '$replacement_value' in $file_path."
    else
        echo "Error: Failed to replace '$search_value' in $file_path."
        return 1
    fi
}

add_line_in_file() {
    # Parameters
    search_folder="$1"   # Folder to search in
    filename="$2"        # Name of the file to find
    new_line="$3"        # Line to add before the original last line

    # Check if the search folder exists
    if [ ! -d "$search_folder" ]; then
        echo "Error: Directory $search_folder does not exist."
        return 1
    fi

    # Find the file in the directory and its subdirectories
    file_path=$(find "$search_folder" -type f -name "$filename" | head -n 1)

    # Check if the file was found
    if [ -z "$file_path" ]; then
        echo "Error: File $filename not found in $search_folder."
        return 1
    fi

    # Append the new line and then re-append the original last line
    echo "Modifying $file_path..."
    sed -i "\$i$new_line" "$file_path" # Add the new line as the second-to-last line

    # Check if the operation succeeded
    if [ $? -eq 0 ]; then
        echo "Successfully added '$new_line' and restored the last line in $file_path."
    else
        echo "Error: Failed to modify $file_path."
        return 1
    fi
}

copy_file_to_same_path() {
    # Parameters
    source_folder="$1"   # Folder to search in
    filename="$2"        # Name of the file to find
    destination_folder="$3" # Destination base folder

    # Check if the source folder exists
    if [ ! -d "$source_folder" ]; then
        echo "Error: Source directory $source_folder does not exist."
        return 1
    fi

    # Check if the destination folder exists
    if [ ! -d "$destination_folder" ]; then
        echo "Error: Destination directory $destination_folder does not exist."
        return 1
    fi

    # Find the file and get its full path
    file_path=$(find "$source_folder" -type f -name "$filename" | head -n 1)

    # Check if the file was found
    if [ -z "$file_path" ]; then
        echo "Error: File $filename not found in $source_folder."
        return 1
    fi

    # Compute the relative path of the file
    relative_path="${file_path#$source_folder/}"

    # Compute the destination path
    destination_path="$destination_folder/$relative_path"

    # Create the destination directory if it doesn't exist
    destination_dir=$(dirname "$destination_path")
    mkdir -p "$destination_dir"

    # Copy the file
    cp "$file_path" "$destination_path"

    # Check if the copy was successful
    if [ $? -eq 0 ]; then
        echo "File copied successfully to $destination_path."
    else
        echo "Error: Failed to copy $filename to $destination_folder."
        return 1
    fi
}




replace_selinux() {
    # Base paths for partitions
    base_path="port"
    selinux_source="patches"

    # Define the partition directories and corresponding selinux paths
    declare -A partition_paths=(
        ["system"]="system/system/etc/selinux"
        ["system_ext"]="system_ext/etc/selinux"
        ["odm"]="odm/etc/selinux"
        ["product"]="product/etc/selinux"
    )

    # Iterate through each partition and replace the selinux folder
    for partition in "${!partition_paths[@]}"; do
        # Define the target path for the selinux folder
        target_path="$base_path/${partition_paths[$partition]}"

        # Remove the existing selinux folder
        echo "Removing old selinux folder at $target_path..."
        sudo rm -rf "$target_path"

        # Copy the new selinux folder from patches
        source_path="$selinux_source/selinux/selinux_$partition"
        if [ -d "$source_path" ]; then
            echo "Copying new selinux folder from $source_path to $target_path..."
            mkdir -p "$(dirname "$target_path")" # Ensure target parent directory exists
            cp -r "$source_path" "$target_path"
        else
            echo "Warning: Source selinux folder for $partition ($source_path) does not exist. Skipping..."
        fi
    done
}

find_file_path() {
    # Parameters
    search_folder="$1"   # Folder to search in
    filename="$2"        # Name of the file to find

    # Check if the search folder exists
    if [ ! -d "$search_folder" ]; then
        echo "Error: Directory $search_folder does not exist."
        return 1
    fi

    # Find the file and get its path
    file_path=$(find "$search_folder" -type f -name "$filename" | head -n 1)

    # Check if the file was found
    if [ -z "$file_path" ]; then
        echo "Error: File $filename not found in $search_folder."
        return 1
    fi

    # Return the file path
    echo "$file_path"
}



mount_images() {
    image_dir="$1"

    # Check if the directory exists
    if [ ! -d "$image_dir" ]; then
        echo "Directory $image_dir does not exist."
        return 1
    fi

    # Check if the directory is "stock"
    if [[ "$(basename "$image_dir")" == "stock" ]]; then
        skip_vendor=true
    else
        skip_vendor=false
    fi

    for image_path in "$image_dir"/*.img; do
        [ -e "$image_path" ] || { echo "No .img files found in $image_dir."; return 1; }

        # Skip images whose filenames contain "boot"
        if [[ "$(basename "$image_path")" == *boot*.img ]]; then
            echo "Skipping $image_path (filename contains 'boot')"
            continue
        fi

        # Skip vendor.img if the directory is "stock"
        if [ "$skip_vendor" == true ] && [[ "$(basename "$image_path")" == "vendor.img" ]]; then
            echo "Skipping $image_path (vendor.img in stock directory)"
            continue
        fi

        partition_name=$(basename "$image_path" .img)

        mount_dir="$image_dir/$partition_name"
        mkdir -p "$mount_dir"

        echo "Mounting $image_path to $mount_dir..."
        sudo mount "$image_path" "$mount_dir"
    done
}


cleanup() {
 sudo umount -f stock/system
 sudo umount -f stock/system_ext
 sudo umount -f stock/vendor
 sudo umount -f stock/product
 sudo umount -f stock/odm
 sudo umount -f port/vendor
 rm -rf tmpout
 rm -rf workdir
}

extract_erofs_images() {
    image_dir="$1"
    specific_image="$2"

    # Check if the directory exists
    if [ ! -d "$image_dir" ]; then
        echo "Directory $image_dir does not exist."
        return 1
    fi

    if [ -n "$specific_image" ]; then
        # If a specific image filename is provided, extract only that image
        image_path="$image_dir/$specific_image"
        if [ ! -f "$image_path" ]; then
            echo "File $image_path does not exist."
            return 1
        fi

        partition_name=$(basename "$image_path" .img)
        extract_dir="$image_dir/$partition_name"
        mkdir -p "$extract_dir"
        
        echo "Extracting $image_path to $extract_dir..."
        fsck.erofs --extract="$extract_dir" --no-preserve --force --overwrite "$image_path"
    else
        # If no specific image is provided, extract all .img files
        for image_path in "$image_dir"/*.img; do
            [ -e "$image_path" ] || { echo "No .img files found in $image_dir."; return 1; }

            partition_name=$(basename "$image_path" .img)
            extract_dir="$image_dir/$partition_name"
            mkdir -p "$extract_dir"

            echo "Extracting $image_path to $extract_dir..."
            fsck.erofs --extract="$extract_dir" --no-preserve --force --overwrite "$image_path"
        done
    fi
}

remove_line_from_file() {
    folder="$1"
    file_name="$2"
    search_str="$3"

    # Check if the folder exists
    if [ ! -d "$folder" ]; then
        echo "Directory $folder does not exist."
        return 1
    fi

    # Search for the file in the folder
    file_path="$folder/$file_name"
    if [ ! -f "$file_path" ]; then
        echo "File $file_name does not exist in $folder."
        return 1
    fi

    # Remove the line containing the search string
    sed -i "/$search_str/d" "$file_path"

    # Check if the operation was successful
    if [ $? -eq 0 ]; then
        echo "Line containing '$search_str' removed from $file_path."
    else
        echo "Failed to remove line from $file_path."
        return 1
    fi
}

delete_32bit_elf_files() {
    folder="$1"

    # Check if the folder exists
    if [ ! -d "$folder" ]; then
        echo "Directory $folder does not exist."
        return 1
    fi

    # List of folder names to skip (relative to the root directory)
    skip_folders=("lib" "firmware" "firmware-modem" "firmware_mnt")

    # Use find to recursively find all files in the folder and its subdirectories
    find "$folder" -type f | while read -r file_path; do
        # Check if the file path contains any of the skip folders
        skip=false
        for skip_folder in "${skip_folders[@]}"; do
            if [[ "$file_path" == *"/$skip_folder/"* ]]; then
                skip=true
                break
            fi
        done

        # If the file is in a folder we want to skip, continue to the next file
        if [ "$skip" == true ]; then
            continue
        fi

        # Check if the file is a 32-bit ELF using the file command
        file_type=$(file -b "$file_path")

        # Check if the file is a 32-bit ELF using grep to match the output
        if echo "$file_type" | grep -q "ELF 32-bit"; then
            echo "Deleting 32-bit ELF file: $file_path"
            rm -f "$file_path"
        fi
    done
}


remove_xml_hal_entry() {
    local xml_file="$1"

    # Check if the XML file exists
    if [ ! -f "$xml_file" ]; then
        echo "The XML file $xml_file does not exist."
        return 1
    fi

    # Remove <hal> entry for vendor.samsung.hardware.security.hdcp.keyprovisioning
    xmlstarlet ed -d '//hal[name="vendor.samsung.hardware.security.hdcp.keyprovisioning"]' "$xml_file" > "$xml_file.tmp" && mv "$xml_file.tmp" "$xml_file"

    # Remove <hal> entry for vendor.samsung.hardware.security.sem without override="true"
    xmlstarlet ed -d '//hal[name="vendor.samsung.hardware.security.sem" and not(@override)]' "$xml_file" > "$xml_file.tmp" && mv "$xml_file.tmp" "$xml_file"

    # Remove <hal> entry for android.hardware.media.omx
    xmlstarlet ed -d '//hal[name="android.hardware.media.omx"]' "$xml_file" > "$xml_file.tmp" && mv "$xml_file.tmp" "$xml_file"

    # Remove <hal> entry for vendor.samsung.hardware.security.sem with override="true"
    xmlstarlet ed -d '//hal[@override="true"][name="vendor.samsung.hardware.security.sem"]' "$xml_file" > "$xml_file.tmp" && mv "$xml_file.tmp" "$xml_file"

    # Remove XML declaration if present
    sed -i '1s/^<?xml version="1.0"?>//' "$xml_file"

    echo "Successfully removed the specified <hal> entries from $xml_file."
}

remove_files_by_name() {
    local folder="$1"
    local names=("${@:2}")  # Take all arguments starting from the second one as an array

    # Check if the folder exists
    if [ ! -d "$folder" ]; then
        echo "The folder $folder does not exist."
        return 1
    fi

    # Iterate over each name in the array
    for name in "${names[@]}"; do
        echo "Removing '$name' ..."

        # Find and remove files with the specified name, skipping 'lib' and 'lib64' directories
        find "$folder" -type f -iname "*$name*" \
            ! -path "$folder/lib*" ! -path "$folder/lib64*" \
            -exec rm -f {} \;
    done
}


append_file_contexts() {
    # Parameters:
    # $1 -> the prefix for the file name (used to find patches/$1_file_contexts)
    # $2 -> the folder path where the target file is located
    # $3 -> the file name to search for in the target file

    folder="$2"
    search_file="$3"
    
    # Construct the full path for the file contexts to append
    contexts_file="patches/$1_file_contexts"

    # Check if the contexts file exists
    if [ ! -f "$contexts_file" ]; then
        echo "The contexts file $contexts_file does not exist."
        return 1
    fi

    # Check if the target folder and file exist
    target_file="$folder/$search_file"
    if [ ! -f "$target_file" ]; then
        echo "The file $target_file does not exist."
        return 1
    fi

    # Read the contents of the contexts file
    contexts_content=$(cat "$contexts_file")

    # Find the position of the search string and append the contexts content after it
    # Ensure to avoid appending at the wrong position or if the search string doesn't exist
    if grep -q "$search_file" "$target_file"; then
        # Use sed to append the content after the search string
        echo "$contexts_content" >> "$target_file"
        echo "Successfully appended the contents of $contexts_file to $target_file."
    else
        echo "The search string $search_file was not found in $target_file."
        return 1
    fi
}

set_device_model() {
    local FILENAME=$1
    local TARGETFILE=$2
    local DIRECTORY=$3
    local MODEL_NAME=$(ls "$FILENAME" | cut -d '_' -f 1)

    case "$MODEL_NAME" in
        "SM-S911B")
            MODEL="Galaxy S23"
            ;;
        "SM-S916B")
            MODEL="Galaxy S23+"
            ;;
        "SM-S918B")
            MODEL="Galaxy S23 Ultra"
            ;;
        *)
            echo "Error: Unknown model $MODEL_NAME"
            return 1
            ;;
    esac

    replace_in_file "$DIRECTORY" "$TARGETFILE" "Galaxy S24" "$MODEL"
}

patch_vendor_cmdline() {
    local boot_img="$1"
    local output_dir="$2"
    local repacked_img="$3"
    local cmdline_entries=("${!4}")  # Accept an array of cmdline entries
    local log_file="$output_dir/unpack.log"

    # Ensure arguments are provided
    if [[ -z "$boot_img" || -z "$output_dir" || -z "$repacked_img" || ${#cmdline_entries[@]} -eq 0 ]]; then
        echo "Usage: repack_vendor_boot <boot_img> <output_dir> <repacked_img> <cmdline_entries_array>"
        return 1
    fi

    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"

    # Unpack the boot image and save the log
    ./bin/mkbootimg/unpack_bootimg.py --boot_img "$boot_img" --out "$output_dir" > "$log_file" || return 1

    # Extract the original vendor_cmdline
    local original_cmdline
    original_cmdline=$(grep "vendor command line args:" "$log_file" | cut -d':' -f2- | xargs)

    # Append entries from the cmdline_entries array
    local new_cmdline="$original_cmdline"
    # for cmdline_entry in "${cmdline_entries[@]}"; do
        new_cmdline="$new_cmdline androidboot.selinux=permissive"
    # done

    # Extract values from the unpack.log
    local dtb_offset
    local ramdisk_offset
    local tags_offset
    local kernel_offset
    local page_size
    local header_version

    dtb_offset=$(grep "dtb address:" "$log_file" | cut -d ':' -f2)
    ramdisk_offset=$(grep "ramdisk load address:" "$log_file" | cut -d ':' -f2)
    tags_offset=$(grep "kernel tags load address:" "$log_file" |cut -d ':' -f2)
    kernel_offset=$(grep "kernel load address:" "$log_file" |cut -d ':' -f2)
    page_size=$(grep "page size:" "$log_file" |cut -d ':' -f2)
    header_version=$(grep "vendor boot image header version:" "$log_file" |cut -d ':' -f2)

    # Repack the boot image with the modified cmdline
    ./bin/mkbootimg/mkbootimg.py \
        --dtb "$output_dir/dtb" \
        --vendor_ramdisk "$output_dir/vendor_ramdisk00" \
        --vendor_cmdline "$new_cmdline" \
        --dtb_offset "$dtb_offset" \
        --ramdisk_offset "$ramdisk_offset" \
        --tags_offset "$tags_offset" \
        --kernel_offset "$kernel_offset" \
        --header_version "$header_version" \
        --pagesize "$page_size" \
        --base 0x00000000 \
        --vendor_bootconfig "$output_dir/bootconfig" \
        --vendor_boot "$repacked_img.img" || return 1

    echo "Repacked image saved to $repacked_img"
    return 0
}

edit_floating_feature() {
    local txtfile="$1"
    local path="$2"

    # Check if the text file exists
    if [[ ! -f "$txtfile" ]]; then
        echo "Error: Text file '$txtfile' not found."
        return 1
    fi

    # Check if the path to floating_feature.xml exists
    local xml_file="$path/floating_feature.xml"
    if [[ ! -f "$xml_file" ]]; then
        echo "Error: XML file '$xml_file' not found."
        return 1
    fi

    # Read the text file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines or lines starting with # (comments)
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi

        # Extract the tag name and value from the XML-like line
        if [[ "$line" =~ \<([a-zA-Z0-9_]+)\>(.+)\</([a-zA-Z0-9_]+)\> ]]; then
            local tag="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Validate that the tag and value match
            if [[ "$tag" != "${BASH_REMATCH[3]}" ]]; then
                echo "Warning: Mismatched tag in line '$line'. Skipping."
                continue
            fi

            # Use xmlstarlet to update the XML file
            xmlstarlet ed -L -u "//$tag" -v "$value" "$xml_file"
            if [[ $? -ne 0 ]]; then
                echo "Error: Failed to update tag '$tag' in XML file."
                return 1
            fi
            echo "Updated tag '$tag' with value '$value'."
        else
            echo "Warning: Invalid line '$line'. Skipping."
        fi
    done < "$txtfile"

    echo "All updates completed."
}

copy_files_from_list() {
    local src_dir="$1"
    local dest_dir="$2"
    local file_list="$3"

    # Check if arguments are provided
    if [[ -z "$src_dir" || -z "$dest_dir" || -z "$file_list" ]]; then
        echo "Usage: copy_files_from_list <source_directory> <destination_directory> <file_list>"
        return 1
    fi

    # Check if source directory exists
    if [[ ! -d "$src_dir" ]]; then
        echo "Source directory does not exist: $src_dir"
        return 1
    fi

    # Check if destination directory exists, create it if not
    if [[ ! -d "$dest_dir" ]]; then
        echo "Destination directory does not exist, creating it: $dest_dir"
        mkdir -p "$dest_dir"
    fi

    # Attempt to locate the file list if it is not found
    if [[ ! -f "$file_list" ]]; then
        local file_list_name=$(basename "$file_list")
        local found_file_list=$(find "$src_dir" -type f -name "$file_list_name" | head -n 1)

        if [[ -n "$found_file_list" ]]; then
            file_list="$found_file_list"
            echo "File list found at: $file_list"
        else
            echo "File list does not exist: $file_list_name"
            return 1
        fi
    fi

    # Copy the file list itself to the destination directory
    local file_list_name=$(basename "$file_list")
    cp "$file_list" "$dest_dir/$file_list_name"
    echo "Copied file list: $file_list -> $dest_dir/$file_list_name"

    # Process each file in the file list
    while IFS= read -r file_path; do
        # Locate the file in the source directory
        local found_file=$(find "$src_dir" -type f -name "$(basename "$file_path")" | head -n 1)

        if [[ -n "$found_file" ]]; then
            # Construct destination path
            local relative_path=$(realpath --relative-to="$src_dir" "$found_file")
            local dest_file="$dest_dir/$relative_path"

            # Create the destination directory structure if necessary
            mkdir -p "$(dirname "$dest_file")"

            # Copy the file, overriding if it already exists
            cp "$found_file" "$dest_file"
            echo "Copied: $found_file -> $dest_file"
        else
            echo "File not found in source directory: $file_path"
        fi
    done < "$file_list"
}


