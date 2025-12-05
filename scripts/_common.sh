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

_extract_cleanup() {
    # Clean up temporary file if it exists
    [ -n "$1" ] && rm -f "$1"
}

extract_project() {
    local project="$1"
    local temp_file=""
    
    # Check if it's a URL or local file
    if [[ "$project" =~ ^https?:// ]]; then
        # It's a URL - download it
        echo "Downloading project from URL: $project"
        temp_file=$(mktemp)
        if ! wget --tries 3 --timeout 900 --no-verbose --output-document="$temp_file" "$project" 2>&1; then
            echo "Error: Failed to download from URL: $project"
            _extract_cleanup "$temp_file"
            return 1
        fi
        
        project="$temp_file"
    fi
    
    # Check if local file exists (just in case)
    if [ ! -f "$project" ]; then
        echo "Error: File not found: $project"
        _extract_cleanup "$temp_file"
        return 1
    fi
    
    # Determine file type (like ynh_setup_source logic)
    local src_format=""
    if [[ "$project" =~ \.zip$ ]]; then
        src_format="zip"
    elif [[ "$project" =~ \.tar\.gz$ ]] || [[ "$project" =~ \.tgz$ ]]; then
        src_format="tar.gz"
    elif [[ "$project" =~ \.tar\.xz$ ]]; then
        src_format="tar.xz"
    elif [[ "$project" =~ \.tar\.bz2$ ]]; then
        src_format="tar.bz2"
    elif [[ "$project" =~ \.tar$ ]]; then
        src_format="tar"
    else
        echo "Error: Unsupported archive format. Supported: .zip, .tar.gz, .tgz, .tar.xz, .tar.bz2, .tar"
        _extract_cleanup "$temp_file"
        return 1
    fi
    
    echo "Extracting project ($src_format) to: $install_dir"

    # Extract based on format (like ynh_setup_source but simplified)
    case "$src_format" in
        "zip")
            if ! unzip -q "$project" -d "$install_dir"; then
                echo "Error: Failed to extract zip file"
                _extract_cleanup "$temp_file"
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
            
            if ! $tar_cmd -xf "$project" -C "$install_dir"; then
                echo "Error: Failed to extract $src_format file"
                _extract_cleanup "$temp_file"
                return 1
            fi
            ;;
        *)
            echo "Error: Unsupported format: $src_format"
            _extract_cleanup "$temp_file"
            return 1
            ;;
    esac
    
    # Check if there's exactly one directory and no files in the root (case where archive has a subfolder)
    pushd "$install_dir"
    
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
    
    popd
    
    # Clean up temporary file
    _extract_cleanup "$temp_file"
    
    echo "Project extracted successfully to: $install_dir"
}