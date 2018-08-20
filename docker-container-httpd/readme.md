# Docker Container 通信

`docker` 容器通信是 `docker` 中最关键、最核心、最常用的功能。其中容器通信包含以下几种通信方式：

+ 外部应用和容器进行通信，外部的应用调用容器进行通信
+ 容器和容器外部应用通信，容器内部调用容器外部的应用进行通信
+ 容器内部相互通信，两个内部的容器进行通信
+ 容器外部相互通信，两个独立的容器进行通信

以上是必须掌握的通信方式，在实际应用场景中会大量重现，下面会一一介绍容器通信的几种方式的配置方式。

# 准备

准备工具 `hoojo/jib-hello` 是一个自定义的镜像，由Java语言开发，主要是测试环境变量中配置的URL 能否通过容器程序访问，避免通过`shell` 频繁操作。



同时，准备一个测试脚本，内容如下：

```sh
$ cat ./test-scripts/test.sh

#!/bin/sh

echo "----------run test script-----------"

echo "ENV_REQUEST_URL: ${ENV_REQUEST_URL}"

OLD_IFS=$IFS
IFS=","
for requrl in ${ENV_REQUEST_URL}; do
	echo
	echo "===> ping ${requrl}"
	#ping -c 1 url
	wget $requrl -O -
	echo
done

IFS=$OLD_IFS
```



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

执行命令启动服务

```sh
$ docker-compose -f docker-compose-external.yaml up 
```

通过 `curl` 能够成功访问容器内部的 `httpd` 访问：

```sh
$ curl localhost:8080
<html><body><h1>It works!</h1></body></html>

$ curl localhost:80
<html><body><h1>It works!</h1></body></html>
```

**总结**：`ports` 可以将端口发布公开到指定机器`IP`上，通过访问`IP：Port`的形式来提供外部应用访问容器服务。

# 容器访问外部应用

**目标**：在容器内部的程序，可以访问外部的应用

**预期**：通过在 `busybox` 内部，能够访问到任何联网的网络应用，包括其他机器设备上的 `docker` 容器或当前机器上的不在同一个 `compose`文件中的容器。

**实现**：编写一个 `compose` 文件，利用 `busybox` 服务在其内部执行 `shell` 访问容器外部的应用 `192.168.99.100:8080 ` (一个独立的 `httpd` 容器，可以理解成 一个独立的应用 )，就像是在当前 `docker` 主机访问应用程序应用一样。

## 方式1、直接通过主机`host`访问

```yaml
$ cat docker-compose-default.yaml

services:

  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app_service
    hostname: app.local
    domainname: hoojo.com
    
    environment:
      # 192.168.99.100 access url success, localhost access url failure.
      - ENV_REQUEST_URL=http://192.168.99.100:80/,http://192.168.99.100:8080/,http://localhost:80/,http://localhost:8080/
      
  app:
    image: busybox:latest
    container_name: app_service
    hostname: app.local
    domainname: hoojo.com
    tty: true
    stdin_open: true
    
    environment:
      - ENV_REQUEST_URL=http://192.168.99.100:80/,http://192.168.99.100:8080/,http://localhost:80/,http://localhost:8080/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh"
```

执行命令启动外部容器或应用 和 测试容器：

```sh
$ docker-compose -f external-access-container/docker-compose-external.yaml up -d
$ docker-compose -f container-assess-external/docker-compose-default.yaml up
```

通过 Java 程序和 Ping  访问配置的URL发现 `localhost` 不能访问

```sh
app_service | ===> ping http://192.168.99.100:80/
app_service | Connecting to 192.168.99.100:80 (192.168.99.100:80)
app_service | <html><body><h1>It works!</h1></body></html>
-                    100% |*******************************|    45   0:00:00 ETA
app_service |
app_service |
app_service | ===> ping http://192.168.99.100:8080/
app_service | Connecting to 192.168.99.100:8080 (192.168.99.100:8080)
app_service | <html><body><h1>It works!</h1></body></html>
-                    100% |*******************************|    45   0:00:00 ETA
app_service |
app_service |
app_service | ===> ping http://localhost:80/
app_service | Connecting to localhost:80 (127.0.0.1:80)
app_service | wget: can't connect to remote host (127.0.0.1): Connection refused
app_service |
app_service |
app_service | ===> ping http://localhost:8080/
app_service | Connecting to localhost:8080 (127.0.0.1:8080)
app_service | wget: can't connect to remote host (127.0.0.1): Connection refused
```

**小结**：直接通过主机IP地址进行外部容器访问，但 `localhost` 则不能访问外部容器或外部应用。

## 方式2、 利用 `network_mode: "host"` 选项配置

```yaml
$ cat docker-compose-net.yaml

version: "3"

services:

  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app_service
    hostname: app.local
    domainname: hoojo.com
    
    network_mode: "host"
    environment:
      # 192.168.99.100 access url success, localhost access url success.
      - ENV_REQUEST_URL=http://192.168.99.100:80/,http://192.168.99.100:8080/,http://localhost:80/,http://localhost:8080/
      
  app:
    image: busybox:latest
    container_name: app_service
    hostname: app.local
    domainname: hoojo.com
    tty: true
    stdin_open: true
    
    network_mode: "host"
    environment:
      - ENV_REQUEST_URL=http://192.168.99.100:80/,http://192.168.99.100:8080/,http://localhost:80/,http://localhost:8080/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh"
```

执行命令进行启动服务和访问外部应用

```sh
# 启动程序
$ docker-compose -f docker-compose-net.yaml up -d
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

## 方式3、利用 `pid: "host"` 选项配置

```yaml
$ cat docker-compose-pid.yaml

services:

  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app_service
    hostname: app.local
    domainname: hoojo.com
    
    pid: "host"
    environment:
      # 192.168.99.100 access url success, localhost access url failure.
      - ENV_REQUEST_URL=http://192.168.99.100:80/,http://192.168.99.100:8080/,http://localhost:80/,http://localhost:8080/
      
  app:
    image: busybox:latest
    container_name: app_service
    hostname: app.local
    domainname: hoojo.com
    tty: true
    stdin_open: true
    
    environment:
      - ENV_REQUEST_URL=http://192.168.99.100:80/,http://192.168.99.100:8080/,http://localhost:80/,http://localhost:8080/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh" 
    
    pid: "host"
```

通过命令进行启动服务并进行测试访问外部应用

```sh
app_service | ===> ping http://192.168.99.100:80/
app_service | Connecting to 192.168.99.100:80 (192.168.99.100:80)
app_service | <html><body><h1>It works!</h1></body></html>
-                    100% |*******************************|    45   0:00:00 ETA
app_service |
app_service |
app_service | ===> ping http://192.168.99.100:8080/
app_service | Connecting to 192.168.99.100:8080 (192.168.99.100:8080)
app_service | <html><body><h1>It works!</h1></body></html>
-                    100% |*******************************|    45   0:00:00 ETA
app_service |
app_service |
app_service | ===> ping http://localhost:80/
app_service | Connecting to localhost:80 (127.0.0.1:80)
app_service | wget: can't connect to remote host (127.0.0.1): Connection refused
app_service |
app_service |
app_service | ===> ping http://localhost:8080/
app_service | Connecting to localhost:8080 (127.0.0.1:8080)
app_service | wget: can't connect to remote host (127.0.0.1): Connection refused
```

**小结**：通过利用 `pid:"host"` 的设置，相当于打开容器与主机操作系统之间的**共享PID地址空间**。这样容器就相当于一个普通的应用暴露在主机指针，用户可以不通过docker 就可以操作容器的进程数据，这将丧失容器的所有隔离的效果。而且，此选项启动的容器**可以访问和主机中的其他容器，反之亦然**。这里在 `app_service` 容器内部不能使用 `localhost `去访问外部的程序，`localhost` 任然指向的是容器内部的IP，而不是当前宿主主机的IP。

# 容器和容器通信

容器和容器通信方式有几种方式可以实现，他们都是在一个 `compose ` 文件中或者 多个 `compose` 文件中的独立容器进行交互访问。在实际应用场景中，多个独立容器相互调用访问是很常见的情况。

## 同一个编排文件中的容器通信

**目标**：在同一个服务编排文件中，在不暴露端口到外部的情况下，让两个独立的容器进行通信。

**预期**：在 `app_service` 服务容器中，可以访问到独立容器 `httpd`。

**实现**：在 `docker-compose-external.yaml` 文件中利用 `app` 服务访问通过 `ports` 提供暴露接口的服务。

### 方式1、通过宿主主机`IP`访问容器

```yaml
version: "3"

services:

  external_httpd:
    image: httpd
    container_name: external_httpd_service
    hostname: httpd.local
    domainname: hoojo.com
    ports:
      - 80:80
      - 8080:80
      
  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app_service
    hostname: app.local
    domainname: hoojo.com
    
    environment:
      # localhost url access failure
      #- ENV_REQUEST_URL=http://localhost:80/,http://localhost:8080/
      # ip access success 
      - ENV_REQUEST_URL=http://192.168.99.100:80/,http://192.168.99.100:8080/
          
  shell_app:
    image: busybox:latest
    container_name: shell_app_service
    hostname: app.local
    domainname: hoojo.com
    tty: true
    stdin_open: true      
```

启动服务：

```sh
 $ docker-compose -f single-compose-container/docker-compose-external.yaml up
```

运行结果如下：

```sh
shell_app_service | ===> ping http://192.168.99.100:81/
shell_app_service | Connecting to 192.168.99.100:81 (192.168.99.100:81)
external_httpd_service | 172.21.0.1 - - [19/Aug/2018:14:56:52 +0000] "GET / HTTP/1.1" 200 45
shell_app_service | <html><body><h1>It works!</h1></body></html>
-                    100% |*******************************|    45   0:00:00 ETA
shell_app_service |
shell_app_service |
shell_app_service | ===> ping http://192.168.99.100:8081/
shell_app_service | Connecting to 192.168.99.100:8081 (192.168.99.100:8081)
shell_app_service | <html><body><h1>It works!</h1></body></html>
-                    100% |*******************************|    45   0:00:00 ETA
shell_app_service |
shell_app_service |
shell_app_service | ===> ping http://localhost:81/
shell_app_service | Connecting to localhost:81 (127.0.0.1:81)
shell_app_service | wget: can't connect to remote host (127.0.0.1): Connection refused
shell_app_service |
shell_app_service |
shell_app_service | ===> ping http://localhost:8081/
shell_app_service | Connecting to localhost:8081 (127.0.0.1:8081)
shell_app_service | wget: can't connect to remote host (127.0.0.1): Connection refused
```

**小结**：由于容器采用 `ports`向外部暴露端口，这就提供了IP访问容器的方法。运行命令启动容器后，发现成功访问 `ENV_REQUEST_URL` 中配置的容器地址。很明显这种方式和之前的几乎一样，结果也是一致 `localhost` 访问容器失败。

### 方式2、`links` 方式，通过容器名称访问

```yaml
$ cat docker-compose-links.yaml

version: "3"
services:

  external_httpd:
    image: httpd
    container_name: external_httpd_service
    hostname: httpd.local
    domainname: hoojo.com
    ports:
      - 80:80
      - 8080:80
      
  internal_httpd:
    image: httpd
    container_name: internal_httpd_service
    hostname: httpd.local
    domainname: hoojo.com
    expose:
      - 80
      
  shell_app:
    image: busybox:latest
    container_name: shell_app
    hostname: app.local
    domainname: hoojo.com
    tty: true
    stdin_open: true      
    
    links:
      - external_httpd:external
      - internal_httpd:internal
    environment:
      # access failure, Connection refused 
      #- ENV_REQUEST_URL=http://external:8080/,http://external_httpd:8080/,http://external_httpd_service:8080/
      
      # access failure, wget: server returned error: HTTP/1.1 403 Forbidden
      #- ENV_REQUEST_URL=http://external:80/,http://external_httpd:80/,http://external_httpd_service:80/

      # access failure, wget: server returned error: HTTP/1.1 403 Forbidden
      # wget: bad address 'internal_httpd_service:80'
      - ENV_REQUEST_URL=http://internal:80/,http://internal_httpd:80/,http://internal_httpd_service:80/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh" 
    
        
  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app
    hostname: app.local
    domainname: hoojo.com
    
    links:
      - external_httpd:external
      - internal_httpd:internal
    volumes:
      - /var/log4j:/var/log4j  
    environment:
      # access failure, Connection refused, 
      #- ENV_REQUEST_URL=http://external:8080/,http://external_httpd:8080/,http://external_httpd_service:8080/
      
      # access success, successfully routed
      #- ENV_REQUEST_URL=http://external:80/,http://external_httpd:80/,http://external_httpd_service:80/
      
      # access success
      - ENV_REQUEST_URL=http://internal:80/,http://internal_httpd:80/,http://internal_httpd_service:80/
```

启动服务：

```sh
$ docker-compose -f single-compose-container/docker-compose-links.yaml up
```

**总结**：`links`  是 docker 版本即将遗弃的功能，后期改用 `network` 的方式使用。`links` 可以将两个不同的容器进行链接，共享容器环境变量和网络，从而能进行网络上的通信。

> **问题**：按照预期，应该在`shell_app`中能够访问到容器，但是一直出现 `HTTP/1.1 403 Forbidden` 这个错误。但`java_app` 可以成功路由到别名或容器、服务名指定的URL。这一点有点匪夷所思，这是一个问题，后期需要进行跟踪！



## 多个编排文件中的容器通信

**目标**：

**预期**：

**实现**：

**总结**：







