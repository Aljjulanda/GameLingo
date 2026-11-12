"""Optional native Windows PDH GPU counters; no polling subprocess or extra dependency."""
import ctypes,re
from ctypes import wintypes

def summarize(samples):
    engines={};processes={}
    for name,value in samples:
        m=re.match(r'pid_(\d+)_(.+?_eng_\d+)_engtype_',name,re.I)
        if not m or not 0<=value<=100:continue
        pid=int(m[1]);engine=m[2]
        engines[engine]=engines.get(engine,0)+value
        per=processes.setdefault(pid,{})
        per[engine]=per.get(engine,0)+value
    return dict(total=round(min(100,max(engines.values(),default=0)),1),
                processes={p:round(min(100,max(e.values(),default=0)),1) for p,e in processes.items()})

class _Number(ctypes.Union):
    _fields_=[('longValue',wintypes.LONG),('doubleValue',ctypes.c_double),('largeValue',ctypes.c_longlong),('stringValue',ctypes.c_void_p)]
class _Value(ctypes.Structure):
    _fields_=[('status',wintypes.DWORD),('number',_Number)]
class _Item(ctypes.Structure):
    _fields_=[('name',wintypes.LPWSTR),('value',_Value)]

class GPU:
    def __init__(self):
        self.query=ctypes.c_void_p();self.counter=ctypes.c_void_p();self.error=''
        try:
            self.api=ctypes.WinDLL('pdh')
            signatures={
                'PdhOpenQueryW':[wintypes.LPCWSTR,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)],
                'PdhAddEnglishCounterW':[ctypes.c_void_p,wintypes.LPCWSTR,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)],
                'PdhCollectQueryData':[ctypes.c_void_p],
                'PdhGetFormattedCounterArrayW':[ctypes.c_void_p,wintypes.DWORD,ctypes.POINTER(wintypes.DWORD),ctypes.POINTER(wintypes.DWORD),ctypes.c_void_p],
                'PdhCloseQuery':[ctypes.c_void_p]}
            for name,types in signatures.items():
                f=getattr(self.api,name);f.argtypes=types;f.restype=wintypes.DWORD
            self._ok(self.api.PdhOpenQueryW(None,0,ctypes.byref(self.query)))
            self._ok(self.api.PdhAddEnglishCounterW(self.query,r'\GPU Engine(*)\Utilization Percentage',0,ctypes.byref(self.counter)))
            self._ok(self.api.PdhCollectQueryData(self.query))
        except Exception as e:self.error=str(e);self.close()
    def _ok(self,status):
        if status:raise OSError(f'PDH 0x{status:08x}')
    def sample(self):
        if not self.query.value:return None
        try:
            self._ok(self.api.PdhCollectQueryData(self.query))
            size=wintypes.DWORD();count=wintypes.DWORD()
            status=self.api.PdhGetFormattedCounterArrayW(self.counter,0x200,ctypes.byref(size),ctypes.byref(count),None)
            if status!=0x800007d2:self._ok(status)
            for _ in range(3):
                buf=ctypes.create_string_buffer(size.value)
                status=self.api.PdhGetFormattedCounterArrayW(self.counter,0x200,ctypes.byref(size),ctypes.byref(count),buf)
                if status!=0x800007d2:break
            self._ok(status)
            items=ctypes.cast(buf,ctypes.POINTER(_Item))
            return summarize((items[i].name,items[i].value.number.doubleValue) for i in range(count.value) if items[i].value.status in (0,1))
        except Exception as e:self.error=str(e);self.close();return None
    def close(self):
        if self.query.value:
            self.api.PdhCloseQuery(self.query);self.query=ctypes.c_void_p()
