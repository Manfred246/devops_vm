"""Local-only DNS forwarder using the Windows resolver for the lab VM."""
import socket,struct,socketserver,datetime
class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        data,sock=self.request
        try:
            pos=12;labels=[]
            while data[pos]:
                n=data[pos];labels.append(data[pos+1:pos+1+n].decode('ascii'));pos+=n+1
            pos+=1;typ,cls=struct.unpack('!HH',data[pos:pos+4]);end=pos+4;name='.'.join(labels)
            family={1:socket.AF_INET,28:socket.AF_INET6}.get(typ)
            answers=[]
            if family:
                try:
                    for item in socket.getaddrinfo(name,None,family,socket.SOCK_STREAM):
                        packed=socket.inet_pton(family,item[4][0])
                        if packed not in answers:answers.append(packed)
                except socket.gaierror:pass
            response=data[:2]+struct.pack('!HHHHH',0x8180,1,len(answers),0,0)+data[12:end]
            for packed in answers:response+=b'\xc0\x0c'+struct.pack('!HHIH',typ,1,60,len(packed))+packed
            sock.sendto(response,self.client_address)
            print(datetime.datetime.now().isoformat(),name,typ,len(answers),flush=True)
        except Exception as exc:print(type(exc).__name__,flush=True)
class Server(socketserver.ThreadingUDPServer):allow_reuse_address=True
with Server(('127.0.0.1',1053),Handler) as server:server.serve_forever()
