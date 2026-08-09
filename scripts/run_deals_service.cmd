@echo off
setlocal
cd /d "%~dp0..\services\deals_ingestion"
python -m qesto_deals serve --host 0.0.0.0 --port 8787 --interval 2700

