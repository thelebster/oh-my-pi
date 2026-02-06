#!/bin/bash
# Object detection (YOLOv8) via AI HAT+
exec rpicam-hello -t 0 --post-process-file /usr/share/rpi-camera-assets/hailo_yolov8_inference.json --lores-width 640 --lores-height 640
