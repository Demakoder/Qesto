/* TEST ONLY: intercept actual SQLite file methods. No alternate SQL engine.
 * Single test process/owner, never attach concurrently or to a live profile.
 * All methods except selected faults delegate to original native VFS.
 */
#include <windows.h>
#include <string.h>
#include "sqlite3.h"
/* The pinned package header is an FFI subset of the public SQLite ABI. */
typedef struct sqlite3_io_methods sqlite3_io_methods;
typedef int64_t sqlite3_int64;
#define SQLITE_OK 0
#define SQLITE_FCNTL_FILE_POINTER 7
#define SQLITE_FCNTL_JOURNAL_POINTER 28
#define API __declspec(dllexport)
typedef struct { sqlite3_file *file; const sqlite3_io_methods *original;
  sqlite3_io_methods hooked; int scope; } Slot;
static Slot slots[32];
static sqlite3_vfs *base_vfs;
static int (*base_open)(sqlite3_vfs*,sqlite3_filename,sqlite3_file*,int,int*);
static int target_scope, target_op, countdown, result_code, behavior, hits;
static __int64 writes, bytes, syncs;
static Slot *find(sqlite3_file *f) {
  int i; for(i=0;i<32;i++) if(slots[i].file==f) return &slots[i];
  return NULL;
}
static int trip(Slot *s,int op) {
  if(s->scope!=target_scope || op!=target_op || countdown<=0) return 0;
  if(--countdown) return 0;
  hits++; if(behavior==2) TerminateProcess(GetCurrentProcess(),86);
  return 1;
}
static int xwrite(sqlite3_file *f,const void *b,int n,sqlite3_int64 off) {
  Slot *s=find(f); int t=trip(s,1),rc;
  writes++; bytes+=n;
  if(t && behavior==0) return result_code;
  if(t && behavior==1) { /* real partial write followed by injected error */
    rc=s->original->xWrite(f,b,n/2,off);
    return rc==SQLITE_OK ? result_code : rc;
  }
  rc=s->original->xWrite(f,b,n,off);
  if(t && behavior==3) TerminateProcess(GetCurrentProcess(),86);
  if(t && behavior==4) return result_code;
  return rc;
}
static int xsync(sqlite3_file *f,int flags) {
  Slot *s=find(f); int t=trip(s,2),rc; syncs++;
  if(t && behavior==0) return result_code;
  rc=s->original->xSync(f,flags);
  if(t && behavior==3) TerminateProcess(GetCurrentProcess(),86);
  if(t && behavior==4) return result_code;
  return rc;
}
static int xtruncate(sqlite3_file *f,sqlite3_int64 size) {
  Slot *s=find(f); int t=trip(s,3),rc;
  if(t && behavior==0) return result_code;
  rc=s->original->xTruncate(f,size);
  if(t && behavior==3) TerminateProcess(GetCurrentProcess(),86);
  return rc;
}
static int xclose(sqlite3_file *f) {
  Slot *s=find(f); const sqlite3_io_methods *original=s->original;
  f->pMethods=original; memset(s,0,sizeof(*s)); return original->xClose(f);
}
static int hook_file(sqlite3_file *file,int scope) {
  int i;
  for(i=0;i<32;i++) if(!slots[i].file) {
    Slot *s=&slots[i]; s->file=file; s->scope=scope;
    s->original=file->pMethods; s->hooked=*file->pMethods;
    s->hooked.xWrite=xwrite; s->hooked.xSync=xsync;
    s->hooked.xTruncate=xtruncate; s->hooked.xClose=xclose;
    file->pMethods=&s->hooked; return 0;
  }
  return -5;
}
static int xopen(sqlite3_vfs *vfs,sqlite3_filename name,sqlite3_file *file,int flags,int *out) {
  int rc=base_open(vfs,name,file,flags,out), scope;
  if(rc!=SQLITE_OK || !file->pMethods) return rc;
  scope=(flags & 0x100)?1:(flags & 0x80000)?2:0;
  if(scope && hook_file(file,scope)!=0) {file->pMethods->xClose(file);file->pMethods=NULL;return 7;}
  return rc;
}
API int qesto_install(void *sqlite_address) {
  HMODULE module;
  typedef sqlite3_vfs *(*FindVfs)(const char*);
  FindVfs vfs_find;
  if(base_vfs) return 0;
  if(!GetModuleHandleExA(6,(LPCSTR)sqlite_address,&module)) return -2;
  vfs_find=(FindVfs)(void*)GetProcAddress(module,"sqlite3_vfs_find");
  if(!vfs_find) return -3;
  /* Hook BELOW MultipleCiphers. Its outer method identity must stay intact. */
  base_vfs=vfs_find("win32");
  if(!base_vfs) return -4;
  base_open=base_vfs->xOpen; base_vfs->xOpen=xopen; return 0;
}
API int qesto_attached(int scope) {
  int i,n=0; for(i=0;i<32;i++) if(slots[i].file && slots[i].scope==scope) n++;
  return n;
}
API void qesto_arm(int scope,int op,int nth,int code,int mode) {
  target_scope=scope; target_op=op; countdown=nth; result_code=code;
  behavior=mode; hits=0;
}
API __int64 qesto_metric(int kind) {
  return kind==0?hits:kind==1?writes:kind==2?bytes:syncs;
}
API double qesto_cpu_ms(void) {
  FILETIME c,e,k,u; ULARGE_INTEGER kernel,user;
  if(!GetProcessTimes(GetCurrentProcess(),&c,&e,&k,&u)) return -1;
  kernel.LowPart=k.dwLowDateTime; kernel.HighPart=k.dwHighDateTime;
  user.LowPart=u.dwLowDateTime; user.HighPart=u.dwHighDateTime;
  return (double)(kernel.QuadPart+user.QuadPart)/10000.0;
}
