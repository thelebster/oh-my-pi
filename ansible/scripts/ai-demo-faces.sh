#!/bin/bash
# Person & face detection (YOLOv5) via AI HAT+
exec rpicam-hello -t 0 --post-process-file /usr/share/rpi-camera-assets/hailo_yolov5_personface.json --lores-width 640 --lores-height 640
