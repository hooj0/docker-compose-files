# Docker Container 通信

docker 容器通信是 docker 中最关键、最核心、最常用的功能。其中容器通信包含以下几种通信方式：

+ 外部应用和容器进行通信，外部的应用调用容器进行通信
+ 容器和容器外部应用通信，容器内部调用容器外部的应用进行通信
+ 容器内部相互通信，两个内部的容器进行通信
+ 容器外部相互通信，两个独立的容器进行通信

以上是必须掌握的通信方式，在实际应用场景中会大量重现，下面会一一介绍容器通信的几种方式的配置方式。

# 外部应用访问容器

**目标**：提供一个容器，暴露指定端口，外部应用可以通过容器所在主机IP地址能够访问到容器。

**预期**：通过 `curl`  或 浏览器等工具，能够请求容器指定接口，发现可以成功访问容器。

**实现**：编写一个简单的 `compose` 文件，将 `httpd` 服务向外部暴露两个端口提供给外部应用访问。

```yaml
$ cat docker-compose-external.yaml

version: "3"

services:

  httpd:
    image: httpd
    container_name: httpd_service
    hostname: httpd.local
    domainname: hoojo.com
    ports:
      - 80:80
      - 8080:80
  
# shell 版本  
$ docker run -p 80:80 -p 8080:80 --name httpd_service httpd:latest 
```

执行命令 `docker-compose -f docker-compose-external.yaml up` 启动服务。

通过 `curl` 能够成功访问容器内部的 `httpd` 访问：

```sh
$ curl localhost:8080
<html><body><h1>It works!</h1></body></html>

$ curl localhost:80
<html><body><h1>It works!</h1></body></html>
```

**总结**：`ports` 可以将端口绑定到指定机器IP上，通过访问`IP：Port`的形式来提供外部应用访问容器服务。

# 容器访问外部应用

**目标**：在容器内部的程序，可以访问外部的应用

**预期**：通过在 `busybox` 内部，能够访问到任何联网的网络应用，包括其他机器设备上的 `docker` 容器或当前机器上的不在同一个 `compose`文件中的容器。

**实现**：编写一个 `compose` 文件，利用 `busybox` 服务在其内部执行 `shell` 访问容器外部的应用 `192.168.99.100:8080 ` (一个独立的 `httpd` 容器，可以理解成 一个独立的应用 )，就像是在当前 `docker` 主机访问应用程序应用一样。

### 实现方式一: 利用 `network_mode: "host"` 选项配置 

```yaml
version: "3"

services:

  app:
    image: busybox:latest
    container_name: app_service
    hostname: app.local
    domainname: hoojo.com
    tty: true
    stdin_open: true
    network_mode: "host"
```

执行命令进行启动服务和访问外部应用

```sh
# 启动程序
$ docker-compose up -d
Starting app_service ... done

# 查看当前主机ip
$ docker-machine ip
192.168.99.100

# 进入容器交互模式，访问外部应用
$ winpty docker attach app_service
/ # ping www.bing.cn
PING www.bing.cn (23.234.4.151): 56 data bytes
64 bytes from 23.234.4.151: seq=0 ttl=54 time=157.785 ms

/ # wget 192.168.99.100:8080 -S
Connecting to 192.168.99.100:8080 (192.168.99.100:8080)
  HTTP/1.1 200 OK
  Date: Sun, 19 Aug 2018 07:31:11 GMT
  Server: Apache/2.4.34 (Unix)
  Last-Modified: Mon, 11 Jun 2007 18:53:14 GMT
  ETag: "2d-432a5e4a73a80"
  Accept-Ranges: bytes
  Content-Length: 45
  Connection: close
  Content-Type: text/html

wget: can't open 'index.html': File exists
/ # wget 192.168.99.100:80 -S
Connecting to 192.168.99.100:80 (192.168.99.100:80)
  HTTP/1.1 200 OK
  Date: Sun, 19 Aug 2018 07:31:20 GMT
  Server: Apache/2.4.34 (Unix)
  Last-Modified: Mon, 11 Jun 2007 18:53:14 GMT
  ETag: "2d-432a5e4a73a80"
  Accept-Ranges: bytes
  Content-Length: 45
  Connection: close
  Content-Type: text/html
  
  / # wget localhost:80 -S
Connecting to localhost:80 (127.0.0.1:80)
  HTTP/1.1 200 OK
  Date: Sun, 19 Aug 2018 07:32:26 GMT
  Server: Apache/2.4.34 (Unix)
  Last-Modified: Mon, 11 Jun 2007 18:53:14 GMT
  ETag: "2d-432a5e4a73a80"
  Accept-Ranges: bytes
  Content-Length: 45
  Connection: close
  Content-Type: text/html

wget: can't open 'index.html': File exists
/ # wget localhost:8080 -S
Connecting to localhost:8080 (127.0.0.1:8080)
  HTTP/1.1 200 OK
  Date: Sun, 19 Aug 2018 07:32:31 GMT
  Server: Apache/2.4.34 (Unix)
  Last-Modified: Mon, 11 Jun 2007 18:53:14 GMT
  ETag: "2d-432a5e4a73a80"
  Accept-Ranges: bytes
  Content-Length: 45
  Connection: close
  Content-Type: text/html
```

**小结**：通过利用 `network_mode: "host"` 对网络模式的设置，让当前服务容器拥有和**主机**应用的网络访问权限能力，在容器内部访问外部的应用，就像在本地访问本机的应用一样。可以把容器理解成一种本地的应用，它不再是具有docker网络的容器。这种模式是一种**不安全的模式**，它丧失了 docker 网络管理的控制，失去了docker 对网络的限制。

### 实现方式二：利用 `pid: "host"` 选项配置

```yaml
version: "3"

services:

  app:
    image: busybox:latest
    container_name: app_service
    hostname: app.local
    domainname: hoojo.com
    tty: true
    stdin_open: true
    pid: "host"
```

通过命令进行启动服务并进行测试访问外部应用

```sh
$ docker attach app_service
/ # wget localhost:8080 -S
Connecting to localhost:8080 (127.0.0.1:8080)
wget: can't connect to remote host (127.0.0.1): Connection refused

/ # wget 127.0.0.1:8080 -S
Connecting to 127.0.0.1:8080 (127.0.0.1:8080)
wget: can't connect to remote host (127.0.0.1): Connection refused

/ # wget 192.168.99.100:80 -S
Connecting to 192.168.99.100:80 (192.168.99.100:80)
  HTTP/1.1 200 OK
  Date: Sun, 19 Aug 2018 07:38:13 GMT
  Server: Apache/2.4.34 (Unix)
  Last-Modified: Mon, 11 Jun 2007 18:53:14 GMT
  ETag: "2d-432a5e4a73a80"
  Accept-Ranges: bytes
  Content-Length: 45
  Connection: close
  Content-Type: text/html

/ # wget 192.168.99.100:8080 -S
Connecting to 192.168.99.100:8080 (192.168.99.100:8080)
  HTTP/1.1 200 OK
  Date: Sun, 19 Aug 2018 07:41:38 GMT
  Server: Apache/2.4.34 (Unix)
  Last-Modified: Mon, 11 Jun 2007 18:53:14 GMT
  ETag: "2d-432a5e4a73a80"
  Accept-Ranges: bytes
  Content-Length: 45
  Connection: close
  Content-Type: text/html
```

**小结**：通过利用 `pid:"host"` 的设置，相当于打开容器与主机操作系统之间的**共享PID地址空间**。这样容器就相当于一个普通的应用暴露在主机指针，用户可以不通过docker 就可以操作容器的进程数据，这将丧失容器的所有隔离的效果。而且，此选项启动的容器**可以访问和主机中的其他容器，反之亦然**。

# 容器和容器通信



## 同一个编排文件中的容器通信

**目标**：

**预期**：

**实现**：

**总结**：



## 多个编排文件中的容器通信

**目标**：

**预期**：

**实现**：

**总结**：







