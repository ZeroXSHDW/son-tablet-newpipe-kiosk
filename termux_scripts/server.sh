#!/data/data/com.termux/files/usr/bin/bash
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib

# Replaces the old netcat server with the new Python dashboard
python3 /data/data/com.termux/files/home/parent_dashboard.py
