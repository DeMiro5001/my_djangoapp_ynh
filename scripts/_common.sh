#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

############################################
# Function to lock a Redis database by setting a dummy key
############################################

redis_lock() {
    local db=$1
    redis-cli -n "$db" SET "ynh_lock" "locked" > /dev/null
}
############################################
# Function to unlock a Redis database by deleting the dummy key
############################################

redis_unlock() {
    local db=$1
    redis-cli -n "$db" DEL "ynh_lock" > /dev/null
}

############################################
# Function to handle project source (local or remote, zip or tar.gz)
############################################

extract_project() {
    local project="$1"
    
    filename=$(basename -- "$project")

    # Check if local file exists (just in case)
    if [[ -f  "$project" ]]; then
        echo "Cpoying $project to $install_dir"
        cp $project $filename
    else
        echo "$project is not a local file"
    fi

    # Check if it's a URL or local file
    if [[ "$project" =~ ^https?:// ]]; then
        # It's a URL - download it
        echo "Downloading project from URL: $project"
        if ! wget --tries 3 --timeout 900 --no-verbose "$project" 2>&1; then
            echo "Error: Failed to download from URL: $project"
            return 1
        fi
    fi

    # Determine file type (like ynh_setup_source logic)
    local src_format=""
    if [[ "$filename" =~ \.zip$ ]]; then
        src_format="zip"
    elif [[ "$filename" =~ \.tar\.gz$ ]] || [[ "$project" =~ \.tgz$ ]]; then
        src_format="tar.gz"
    elif [[ "$filename" =~ \.tar\.xz$ ]]; then
        src_format="tar.xz"
    elif [[ "$filename" =~ \.tar\.bz2$ ]]; then
        src_format="tar.bz2"
    elif [[ "$filename" =~ \.tar$ ]]; then
        src_format="tar"
    else
        echo "Error: Unsupported archive format. Supported: .zip, .tar.gz, .tgz, .tar.xz, .tar.bz2, .tar"
        return 1
    fi
    
    echo "Extracting project ($src_format) to: $install_dir"
    
    # Extract based on format (like ynh_setup_source but simplified)
    case "$src_format" in
        "zip")
            if ! unzip -q "$filename" -d "$install_dir"; then
                echo "Error: Failed to extract zip file"
                return 1
            fi
            ;;
        "tar.gz"|"tar.xz"|"tar.bz2"|"tar")
            local tar_cmd="tar"
            case "$src_format" in
                "tar.gz") tar_cmd="tar -z";;
                "tar.xz") tar_cmd="tar -J";;
                "tar.bz2") tar_cmd="tar -j";;
                "tar") tar_cmd="tar";;
            esac
            
            if ! $tar_cmd -xf "$filename" -C "$install_dir"; then
                echo "Error: Failed to extract $src_format file"
                return 1
            fi
            ;;
        *)
            echo "Error: Unsupported format: $src_format"
            return 1
            ;;
    esac

    ynh_safe_rm $filename
    
    # Count items in current directory, if there's exactly one directory and no files, move contents up
    local items=(*)
    local dirs=()
    local files=()
    
    for item in "${items[@]}"; do
        if [ -d "$item" ]; then
            dirs+=("$item")
        elif [ -f "$item" ]; then
            files+=("$item")
        fi
    done

    if [ "${#dirs[@]}" -eq 1 ] && [ "${#files[@]}" -eq 0 ]; then
        echo "Moving contents from subdirectory: ${dirs[0]}"
        
        mv "${dirs[0]}"/* "${dirs[0]}"/.[!.]* . 2>/dev/null || true
        
        rmdir "${dirs[0]}" 2>/dev/null || true
    fi
    
    echo "Project extracted successfully to: $install_dir"
}
