#!/usr/bin/env python3
import os
import sys
import json
from PIL import Image

def generate_icons(source_path, appiconset_path):
    print(f"Source Image: {source_path}")
    print(f"Asset Catalog Path: {appiconset_path}")
    
    contents_json_path = os.path.join(appiconset_path, "Contents.json")
    if not os.path.exists(contents_json_path):
        print(f"Error: {contents_json_path} does not exist.")
        sys.exit(1)
        
    with open(contents_json_path, 'r') as f:
        data = json.load(f)
        
    images = data.get("images", [])
    if not images:
        print("Error: No images found in Contents.json")
        sys.exit(1)
        
    try:
        source_img = Image.open(source_path)
        # Ensure image is RGB (no alpha channel for standard iOS/macOS icons if not needed)
        if source_img.mode != 'RGB':
            source_img = source_img.convert('RGB')
    except Exception as e:
        print(f"Error opening source image: {e}")
        sys.exit(1)
        
    processed_files = set()
    
    for img_entry in images:
        filename = img_entry.get("filename")
        if not filename:
            continue
            
        if filename in processed_files:
            # Already generated this file (e.g. universal dark/tinted using the same filename)
            continue
            
        size_str = img_entry.get("size")
        scale_str = img_entry.get("scale", "1x")
        
        # Parse size (e.g., "16x16" or "1024x1024")
        try:
            w_str, h_str = size_str.split('x')
            width = float(w_str)
            height = float(h_str)
        except Exception:
            print(f"Warning: Could not parse size '{size_str}' for entry {img_entry}")
            continue
            
        # Parse scale (e.g., "2x" or "1x")
        try:
            scale = float(scale_str.replace('x', ''))
        except Exception:
            scale = 1.0
            
        target_w = int(round(width * scale))
        target_h = int(round(height * scale))
        
        target_path = os.path.join(appiconset_path, filename)
        
        print(f"Generating {filename} ({target_w}x{target_h}) from {size_str} @ {scale_str}...")
        
        try:
            # Resize using Lanczos filter
            resized_img = source_img.resize((target_w, target_h), Image.Resampling.LANCZOS)
            resized_img.save(target_path, "PNG")
            processed_files.add(filename)
        except Exception as e:
            print(f"Error generating {filename}: {e}")
            
    print("\nSuccessfully updated all app icons!")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 generate_icons.py <source_image_path> <appiconset_path>")
        sys.exit(1)
        
    generate_icons(sys.argv[1], sys.argv[2])
