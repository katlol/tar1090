#!/bin/bash
set -ex
{
    spritename="sprites_$(md5sum images/sprites.png | cut -d' ' -f1).png"
    mv "images/sprites.png" "images/${spritename}"
    sed -i -e "s#sprites.png#${spritename}#g" script.js
    sed -i -e "s#sprites.png#${spritename}#g" index.html
}

# cache busting js / css
{
    sedargs=("sed" "-i" "index.html")
    for file in dbloader.js defaults.js early.js flags.js formatter.js layers.js markers.js planeObject.js registrations.js script.js style.css; do
        md5sum=$(md5sum $file | cut -d' ' -f1)
        prefix=$(cut -d '.' -f1 <<< "$file")
        postfix=$(cut -d '.' -f2 <<< "$file")
        newname="${prefix}_${md5sum}.${postfix}"
        mv "$file" "$newname"
        sedargs+=("-e" "s#${file}#${newname}#")
    done

    "${sedargs[@]}"
}
