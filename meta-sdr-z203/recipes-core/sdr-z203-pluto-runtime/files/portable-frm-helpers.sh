copy_without_trailing_bytes() {
    in_file="$1"
    out_file="$2"
    trailing_bytes="$3"
    total_size=$(wc -c < "$in_file")
    data_size=$((total_size - trailing_bytes))
    [ "$data_size" -gt 0 ] || return 1
    dd if="$in_file" of="$out_file" bs="$data_size" count=1 2>/dev/null
}
