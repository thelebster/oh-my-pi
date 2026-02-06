#!/bin/bash
# Image segmentation (YOLOv5) via AI HAT+
exec rpicam-hello -t 0 --post-process-file /usr/share/rpi-camera-assets/hailo_yolov5_segmentation.json --lores-width 640 --lores-height 640 --framerate 20
