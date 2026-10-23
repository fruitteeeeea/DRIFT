"""Run only against the disposable DB initialized by guestbook.sql."""
import concurrent.futures
import os
import subprocess

url = os.environ['TEST_DATABASE_URL']
def sql(statement):
    return subprocess.run(['psql', url, '-X', '-v', 'ON_ERROR_STOP=1', '-c', statement], capture_output=True, text=True)

setup = sql("update drift_private.guestbook_guard set enabled=true, recent='[]';")
assert setup.returncode == 0, setup.stderr
with concurrent.futures.ThreadPoolExecutor(max_workers=20) as pool:
    results = list(pool.map(lambda n: sql(f"set role anon; insert into public.drift_messages(content) values ('concurrent-{n}');"), range(20)))
assert sum(r.returncode == 0 for r in results) == 10, [(r.returncode, r.stderr) for r in results]
assert all(r.returncode == 0 or 'guestbook_rate_limited' in r.stderr for r in results)
print('20 concurrent direct inserts: exactly 10 accepted, 10 rate limited')
