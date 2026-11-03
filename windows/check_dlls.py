"""CI check for the built Windows DLLs: regsvr32 and TSF find their entry points by exact name,
and the DLL loads on a fresh PC (no Visual C++ runtime import).

  pip install pefile && python windows/check_dlls.py <typer_tsf.dll>...
"""
import sys

import pefile

NEED = {"DllGetClassObject", "DllCanUnloadNow", "DllRegisterServer", "DllUnregisterServer"}

failed = False
for path in sys.argv[1:]:
    pe = pefile.PE(path)
    exports = {s.name.decode() for s in pe.DIRECTORY_ENTRY_EXPORT.symbols if s.name}
    imports = sorted(i.dll.decode().lower() for i in pe.DIRECTORY_ENTRY_IMPORT)
    missing = NEED - exports
    runtime = [d for d in imports if d.startswith(("vcruntime", "msvcp", "api-ms-win-crt"))]
    print(f"{path}\n  exports: {sorted(exports)}\n  imports: {imports}")
    if missing or runtime:
        failed = True
        print(f"  FAIL: missing exports {sorted(missing)}, needs C runtime {runtime}")
sys.exit(failed)
