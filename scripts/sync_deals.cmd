@echo off
setlocal
cd /d "%~dp0..\services\deals_ingestion"
python -m qesto_deals sync

