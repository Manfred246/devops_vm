"""Pinned SSH transport through Windows when VPN blocks WSL sockets.

Ansible modules still run on the Ubuntu VM. Only the SSH client is moved
to the Windows host; no host-key verification or encryption is disabled.
"""
import base64
import json
import subprocess

from ansible.errors import AnsibleConnectionFailure
from ansible.plugins.connection import ConnectionBase

DOCUMENTATION = r'''
name: windows_bridge
short_description: Run pinned Paramiko SSH from the Windows host
description: Bridge WSL stdin and files to the existing Windows SSH key.
author: DevOps lab
options:
  bridge_python:
    description: WSL path of the Windows bundled Python runtime.
    type: str
    vars:
      - name: ansible_bridge_python
  bridge_dependencies:
    description: Windows path of the installed Paramiko modules.
    type: str
    vars:
      - name: ansible_bridge_dependencies
  bridge_known_hosts:
    description: Windows path of the pinned known_hosts file.
    type: str
    vars:
      - name: ansible_bridge_known_hosts
'''

HELPER = r'''
import sys,json,base64,traceback
c=None
try:
 for line in sys.stdin.buffer:
  try:
    p=json.loads(line)
    if c is None:
        sys.path.insert(0,p['dependencies'])
        import paramiko
        c=paramiko.SSHClient()
        c.load_host_keys(p['known_hosts'])
        c.set_missing_host_key_policy(paramiko.RejectPolicy())
        c.connect(p['host'],port=p['port'],username=p['user'],key_filename=p['key'],
                  look_for_keys=False,allow_agent=False,timeout=15)
    if p['operation']=='exec':
        si,so,se=c.exec_command(p['command'])
        si.write(base64.b64decode(p['input']));si.flush();si.channel.shutdown_write()
        out=so.read();err=se.read();rc=so.channel.recv_exit_status()
    else:
        with c.open_sftp() as s:
            if p['operation']=='put':
                with s.file(p['remote'],'wb') as f:f.write(base64.b64decode(p['input']))
                out=b''
            else:
                with s.file(p['remote'],'rb') as f:out=f.read()
        err=b'';rc=0
    print(json.dumps({'rc':rc,'out':base64.b64encode(out).decode(),'err':base64.b64encode(err).decode()}),flush=True)
  except Exception:
    print(json.dumps({'error':traceback.format_exc()}),flush=True)
finally:
 if c is not None:c.close()
'''


class Connection(ConnectionBase):
    """Use Windows sockets without changing the VM or VPN configuration."""
    transport = 'windows_bridge'
    has_pipelining = True

    def _connect(self):
        self._connected = True
        return self

    def _call(self, operation, command='', data=b'', remote=''):
        p = dict(operation=operation,command=command,input=base64.b64encode(data).decode(),remote=remote,
                 host=self._play_context.remote_addr,port=self._play_context.port or 22,
                 user=self._play_context.remote_user,key=self._play_context.private_key_file,
                 dependencies=self.get_option('bridge_dependencies'),
                 known_hosts=self.get_option('bridge_known_hosts'))
        if getattr(self,'_proc',None) is None:
            self._proc=subprocess.Popen([self.get_option('bridge_python'),'-u','-c',HELPER],
                                         stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        self._proc.stdin.write(json.dumps(p).encode()+b'\n')
        self._proc.stdin.flush()
        response=self._proc.stdout.readline()
        if not response:
            raise AnsibleConnectionFailure(self._proc.stderr.read().decode(errors='replace'))
        try:
            value=json.loads(response)
        except ValueError as exc:
            raise AnsibleConnectionFailure('Invalid SSH bridge response') from exc
        if 'error' in value:raise AnsibleConnectionFailure(value['error'])
        return value['rc'],base64.b64decode(value['out']),base64.b64decode(value['err'])

    def exec_command(self, cmd, in_data=None, sudoable=True):
        super().exec_command(cmd,in_data=in_data,sudoable=sudoable)
        data = in_data or b''
        if sudoable and self.become:
            password = self.become.get_option('become_pass')
            if password and self.become.check_success(cmd.encode()):
                data = password.encode() + b'\n' + data
        return self._call('exec',command=cmd,data=data)

    def put_file(self, in_path, out_path):
        super().put_file(in_path,out_path)
        with open(in_path,'rb') as stream:self._call('put',data=stream.read(),remote=out_path)

    def fetch_file(self, in_path, out_path):
        super().fetch_file(in_path,out_path)
        _,data,_=self._call('fetch',remote=in_path)
        with open(out_path,'wb') as stream:stream.write(data)

    def close(self):
        if getattr(self,'_proc',None) is not None:
            self._proc.stdin.close()
            try:self._proc.wait(timeout=5)
            except subprocess.TimeoutExpired:self._proc.terminate()
            self._proc=None
        self._connected = False
