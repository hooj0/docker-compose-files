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

### 方式1、直接访问容器

```yaml
$ cat docker-compose-internal.yaml

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
      
  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app
    hostname: app.local
    domainname: hoojo.com
    
    environment:
      # SERVICE NAME
      # http://external_httpd:8080 access failure, Connect to external_httpd:8080 [external_httpd/172.22.0.2] failed: Connection refused
      # port 80 access successful
      #- ENV_REQUEST_URL=http://external_httpd:80/,http://external_httpd:8080/,http://internal_httpd:80/
      
      # CONTAINER NAME
      # access successful 
      - ENV_REQUEST_URL=http://internal_httpd_service:80/,http://internal_httpd_service:80/
      
  shell_app:
    image: busybox:latest
    container_name: shell_app
    hostname: app.local
    domainname: hoojo.com
    tty: true
    stdin_open: true     
    
    environment:
      # SERVICE NAME
      # wget: server returned error: HTTP/1.1 403 Forbidden
      #- ENV_REQUEST_URL=http://external_httpd:80/,http://external_httpd:8080/,http://internal_httpd:80/

      # CONTAINER NAME
      # wget: server returned error: HTTP/1.1 403 Forbidden
      - ENV_REQUEST_URL=http://internal_httpd_service:80/,http://internal_httpd_service:80/
      
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh"  
```

启动服务：

```sh
$ docker-compose -f single-compose-container/docker-compose-internal.yaml up
```

**总结**：由于是内部调用，只能访问内部的端口，而不是指向外部`ports`的端口，所以在调用的时候必须设置内部端口，而不能配置外部端口。

### 方式2、通过宿主主机`IP`访问容器

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

**总结**：由于容器采用 `ports`向外部暴露端口，这就提供了IP访问容器的方法。运行命令启动容器后，发现成功访问 `ENV_REQUEST_URL` 中配置的容器地址。很明显这种方式和之前的几乎一样，结果也是一致 `localhost` 访问容器失败。

### 方式3、`links` 方式，通过容器名称访问

```yaml
$ cat docker-compose-links.yaml

version: "3"
services:

  external_httpd:
    image: httpd
    container_name: external_httpd_service
    ports:
      - 80:80
      - 8080:80
      
  internal_httpd:
    image: httpd
    container_name: internal_httpd_service
    expose:
      - 80
      
  shell_app:
    image: busybox:latest
    container_name: shell_app
    tty: true
    stdin_open: true      
    
    links:
      - external_httpd:external
      - internal_httpd:internal
    environment:
      # access failure, Connection refused 
      #- ENV_REQUEST_URL=http://external:8080/,http://external_httpd:8080/,http://external_httpd_service:8080/
           
      #- ENV_REQUEST_URL=http://external:80/,http://external_httpd:80/,http://external_httpd_service:80/
     
      - ENV_REQUEST_URL=http://internal:80/,http://internal_httpd:80/,http://internal_httpd_service:80/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh" 
    
        
  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app
    
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

**总结**：`links`  是 docker 版本即将遗弃的功能，后期推荐使用 `network` 的方式。`links` 可以将两个不同的容器进行链接，共享容器环境变量和网络，从而能进行网络上的通信。使用`links`的方式可以在**不向外部暴露端口**的方式，进行容器之前的通信。

### 方式4、`networks`方式，通过网络别名访问

```yaml
$ cat docker-compose-network.yaml


services:
  external_httpd:
    image: httpd
    container_name: external_httpd_service
    ports:
      - 80:80
      - 8080:80
    networks:
      default:
        aliases:
         - external-a
         - external-b  
      
  internal_httpd:
    image: nginx
    container_name: internal_httpd_service
    expose:
      - 80
    networks:
      default:
        aliases:
         - internal
      
  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app
    
    networks:
      - default
    environment:
      # internal access failure, ERROR -> request failure, status: 405
      # external-* access successful
      - ENV_REQUEST_URL=http://external-b:80/,http://external-a:80/,http://internal:80/
    
  shell_app:
    image: busybox:latest
    container_name: shell_app
    tty: true
    stdin_open: true      
    
    networks:
      - default
    environment:
      - ENV_REQUEST_URL=http://external-b:80/,http://external-a:80/,http://internal:80/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh" 
```

运行命令启动服务：

```sh
$ docker-compose -f single-compose-container/docker-compose-network.yaml up
```

测试结果如下：

```sh
java_app          | INFO -> request url: http://external-b:80/
external_httpd_service | 172.22.0.2 - - [20/Aug/2018:06:02:19 +0000] "POST /?timed=1534744939511 HTTP/1.1" 200 45
java_app          | INFO -> result: <html><body><h1>It works!</h1></body></html>
java_app          |
java_app          | INFO -> host: external-b, port: 80, addr: null, scheme: http
java_app          |
java_app          | INFO -> request url: http://external-a:80/
external_httpd_service | 172.22.0.2 - - [20/Aug/2018:06:02:19 +0000] "POST /?timed=1534744939938 HTTP/1.1" 200 45
java_app          | INFO -> result: <html><body><h1>It works!</h1></body></html>
java_app          |
java_app          | INFO -> host: external-a, port: 80, addr: null, scheme: http
java_app          |
java_app          | INFO -> request url: http://internal:80/
internal_httpd_service | 172.22.0.2 - - [20/Aug/2018:06:02:19 +0000] "POST /?timed=1534744939961 HTTP/1.1" 405 173 "-" "Apache-HttpClient/4.5.5 (Java/1.8.0_131)" "-"
java_app          | ERROR -> request failure, status: 405
java_app          |
java_app          | INFO -> host: internal, port: 80, addr: null, scheme: http
java_app exited with code 0
shell_app         | Connecting to external-b:80 (54.183.99.63:80)
shell_app         | wget: server returned error: HTTP/1.1 403 Forbidden
shell_app         |
shell_app         |
shell_app         | ===> ping http://external-a:80/
shell_app         | Connecting to external-a:80 (54.183.99.63:80)
shell_app         | wget: server returned error: HTTP/1.1 403 Forbidden
shell_app         |
shell_app         |
shell_app         | ===> ping http://internal:80/index.html
shell_app         | Connecting to internal:80 (54.183.99.63:80)
shell_app         | wget: server returned error: HTTP/1.1 403 Forbidden
```

**总结**：正常情况下，可以通过网络别名访问容器，访问容器和当前应用必须在**同一个网络环境中**，而且访问的方式是通过暴露在外部`ports`的端口访问，而内部`expose`暴露端口的方式则不能访问。

## 多个编排文件中的容器通信

**目标**：在多个`compose file` 文件编排服务的情况下，能进行容器服务之间的信息互通。

**预期**：在文件 `A` 中定义两个不同的 `httpd` 服务，在文件`B`中可以访问到`httpd`服务或容器。

**实现**：在 `compose-based.yaml`中定义两个不同的 `httpd` 服务，在另一个`compose.yaml`文件中可以访问到文件`compose-based.yaml`中定义服务或容器。

### 方式1、直接通过`host`访问外部容器

提供`httpd`服务

```yaml
$ cat docker-compose-httpd.yaml

services:
  external_httpd:
    image: httpd
    container_name: external_httpd_service
    ports:
      - 8080:80
    
  internal_httpd:
    image: httpd
    container_name: internal_httpd_service
    expose:
      - 80
```

提供测试程序

```yaml
$ cat docker-compose-host.yaml

services:

  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app
    
    environment:
      - ENV_REQUEST_URL=http://192.168.99.100:80/,http://192.168.99.100:8080/
    
  shell_app:
    image: busybox:latest
    container_name: shell_app
    tty: true
    stdin_open: true     
    
    environment:
      - ENV_REQUEST_URL=http://192.168.99.100:80/,http://192.168.99.100:8080/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh"
```

启动服务程序：

```sh
$ docker-compose -f multiple-compose-container/ip-host/docker-compose-httpd.yaml up -d
$ docker-compose -f multiple-compose-container/ip-host/docker-compose-host.yaml up
```

运行结果如下：

```sh
shell_app    | ===> ping http://192.168.99.100:80/
shell_app    | Connecting to 192.168.99.100:80 (192.168.99.100:80)
shell_app    | wget: can't connect to remote host (192.168.99.100): Connection refused
shell_app    |
shell_app    |
shell_app    | ===> ping http://192.168.99.100:8080/
shell_app    | Connecting to 192.168.99.100:8080 (192.168.99.100:8080)
shell_app    | <html><body><h1>It works!</h1></body></html>
-                    100% |*******************************|    45   0:00:00 ETA
shell_app    |
java_app     |
java_app     | INFO -> request url: http://192.168.99.100:80/
java_app     | ERROR -> Connect to 192.168.99.100:80 [/192.168.99.100] failed: Connection refused (Connection refused)
java_app     |
java_app     | INFO -> request url: http://192.168.99.100:8080/
java_app     | INFO -> result: <html><body><h1>It works!</h1></body></html>

```

**总结**：`docker-compose-httpd.yaml`是服务提供者，`docker-compose-host.yaml`是服务调用者。双方在通过当前宿主主机的IP进行服务调用，成功访问到外部容器`external_httpd`，而内部容器`internal_httpd`则调用失败。

### 方式2、`network_mode: "host"` 主机网络模式访问外部容器

提供`httpd`服务

```yaml
$ cat docker-compose-httpd.yaml

services:
  external_httpd:
    image: httpd
    container_name: external_httpd_service
    ports:
      - 8080:80
    
  internal_httpd:
    image: httpd
    container_name: internal_httpd_service
    expose:
      - 80
```

提供测试程序

```yaml
$ cat docker-compose-net.yaml

services:
  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app
    
    network_mode: "host"
    environment:
      # ports 8080 access successful, expose 80 access failure.
      - ENV_REQUEST_URL=http://localhost:80/,http://localhost:8080/,http://192.168.99.100:8080/
    
  shell_app:
    image: busybox:latest
    container_name: shell_app
    tty: true
    stdin_open: true     
    
    network_mode: "host"
    environment:
      # ports 8080 access successful, expose 80 access failure.
      - ENV_REQUEST_URL=http://localhost:80/,http://localhost:8080/,http://192.168.99.100:8080/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh"  
```

启动服务：

```sh
$ docker-compose -f multiple-compose-container/net-host/docker-compose-httpd.yaml up -d
$ docker-compose -f multiple-compose-container/net-host/docker-compose-net.yaml up
```

执行结果：

```sh
shell_app    | ===> ping http://localhost:80/
shell_app    | Connecting to localhost:80 (127.0.0.1:80)
shell_app    | wget: can't connect to remote host (127.0.0.1): Connection refused
shell_app    |
shell_app    |
shell_app    | ===> ping http://localhost:8080/
shell_app    | Connecting to localhost:8080 (127.0.0.1:8080)
shell_app    | <html><body><h1>It works!</h1></body></html>
-                    100% |*******************************|    45   0:00:00 ETA
shell_app    |
shell_app    |
shell_app    | ===> ping http://192.168.99.100:8080/
shell_app    | Connecting to 192.168.99.100:8080 (192.168.99.100:8080)
shell_app    | <html><body><h1>It works!</h1></body></html>
-                    100% |*******************************|    45   0:00:00 ETA
shell_app    |
java_app     | INFO -> request url: http://localhost:80/
java_app     | ERROR -> Connect to localhost:80 [localhost/127.0.0.1] failed: Connection refused (Connection refused)
java_app     |
java_app     | INFO -> request url: http://localhost:8080/
java_app     | INFO -> result: <html><body><h1>It works!</h1></body></html>
java_app     |
java_app     | INFO -> host: localhost, port: 8080, addr: null, scheme: http
java_app     |
java_app     | INFO -> request url: http://192.168.99.100:8080/
java_app     | INFO -> result: <html><body><h1>It works!</h1></body></html>
java_app     |
java_app     | INFO -> host: 192.168.99.100, port: 8080, addr: null, scheme: http
```

### 方式3、`network_mode: "container"`加入到容器进行访问

提供测试程序

```yaml
$ cat docker-compose-join.yaml


services:

  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app
    
    network_mode: "container:external_httpd_service"
    #network_mode: "container:internal_httpd_service"
    environment:
      # access successful
      - ENV_REQUEST_URL=http://external_httpd_service:8080/
      
      # access successful
      #- ENV_REQUEST_URL=http://internal_httpd_service:80/
    
  shell_app:
    image: busybox:latest
    container_name: shell_app
    tty: true
    stdin_open: true     
    
    network_mode: "container:external_httpd_service"
    #network_mode: "container:internal_httpd_service"
    environment:     
      - ENV_REQUEST_URL=http://external_httpd_service:8080/      
      #- ENV_REQUEST_URL=http://internal_httpd_service:80/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh"  
```

启动服务：

```sh
$ docker-compose -f multiple-compose-container/net-host/docker-compose-httpd.yaml up -d
$ docker-compose -f multiple-compose-container/net-container/docker-compose-join.yaml up
```

**总结**：`network_mode: "container:[container name/id]"`是加入容器的方式，这种方式只能每次只能加入一个容器进行链接，是一种被动的方式。通过在调用方加入到提供方的容器中，进行链接。相反，在提供方加入调用方，每次也只能加入一个。通过加入容器后，可以直接通过加入容器的名称进行调用容器服务进行通信。

### 方式4、`external_links` 方式，通过容器名称或别名访问外部容器

服务提供方：

```yaml
$ cat docker-compose-httpd.yaml

services:
  external_httpd:
    image: httpd
    container_name: external_httpd_service
    ports:
      - 8080:80
    
  internal_httpd:
    image: httpd
    container_name: internal_httpd_service
    expose:
      - 80
```

服务调用方：

```yaml
$ cat docker-compose-links.yaml

services:

  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app
    
    external_links:
      - internal_httpd_service
      - external_httpd_service
      - external_httpd_service:external
      
    environment:
      # ports 8080 access failure, expose 80 access success.
      #- ENV_REQUEST_URL=http://internal_httpd_service:80/,http://external_httpd_service:8080/,http://external:8080/
      
      # access successful
      - ENV_REQUEST_URL=http://external_httpd_service:80/,http://external:80/
    
  shell_app:
    image: busybox:latest
    container_name: shell_app
    tty: true
    stdin_open: true     
    
    external_links:
      - internal_httpd_service
      - external_httpd_service
      - external_httpd_service:external
      
    environment:      
      #- ENV_REQUEST_URL=http://internal_httpd_service:80/,http://external_httpd_service:8080/,http://external:8080/
      
      - ENV_REQUEST_URL=http://external_httpd_service:80/,http://external:80/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh"  
```

启动服务：

```sh
$ docker-compose -f multiple-compose-container/external-links/docker-compose-httpd.yaml up -d
$ docker-compose -f multiple-compose-container/external-links/docker-compose-links.yaml up
```

**总结**：`external_links` 相当于将两个不同的文件合并为一个文件。通过链接的容器名称或者别名能成功访问容器**内部暴露的端口**进行通信。而暴露在外部的端口则不能正常访问！

### 方式5、`networks-alias` 进行加入相同网络进行通信

服务提供方：

```yaml
$ cat docker-compose-httpd.yaml

services:
  external_httpd:
    image: httpd
    container_name: external_httpd_service
    ports:
      - 8080:80
    networks:
      common-net:
        aliases:
         - external-a
         - external-b  
    
  internal_httpd:
    image: httpd
    container_name: internal_httpd_service
    expose:
      - 80
    networks:
      common-net:
        aliases:
         - internal

networks:
  common-net:
    external:
      name: my-net 
```

服务调用方：

```yaml
$ cat docker-compose-network.yaml

services:

  java_app:
    image: hoojo/jib-hello:1.0
    container_name: java_app
    
    networks:
      - common-net
    environment:
    
    # NETWORK ALIAS ACCESS
      # access successful
      - ENV_REQUEST_URL=http://external-b:80/,http://external-a:80/,http://internal:80/
      
    # CONTAINER NAME ACCESS
      # access successful
      - ENV_REQUEST_URL=http://external_httpd_service:80/,http://internal_httpd_service:80/  

    # SERVICE NAME ACCESS
      # access successful
      - ENV_REQUEST_URL=http://external_httpd:80/,http://internal_httpd:80/  
    
  shell_app:
    image: busybox:latest
    container_name: shell_app
    tty: true
    stdin_open: true      
    
    networks:
      - common-net
    environment:
      # NETWORK ALIAS ACCESS
      - ENV_REQUEST_URL=http://external-b:80/,http://external-a:80/,http://internal:80/
      
      # CONTAINER NAME ACCESS
      - ENV_REQUEST_URL=http://external_httpd_service:80/,http://internal_httpd_service:80/
      
      # SERVICE NAME ACCESS
      - ENV_REQUEST_URL=http://external_httpd:80/,http://internal_httpd:80/
    volumes:
      - "/mnt/docker-container-httpd/test-scripts:/test-scripts:ro"
    command: "sh -c ./test-scripts/test.sh"
    
networks:
  common-net:
    external:
      name: my-net 
```

运行命令启动服务：

```sh
$ docker network create my-net

$ docker-compose -f multiple-compose-container/networks-alias/docker-compose-httpd.yaml up -d
$ docker-compose -f multiple-compose-container/networks-alias/docker-compose-network.yaml up
```

**总结**：通过将容器都加入到同一个网络中，相当于把这些容器都联通。这样通过网络服务的别名、容器名称、服务名称，都能够访问到容器本身的内部端口，而非暴露在外部的端口。

# 问题清单
+ 1、hostname、domain 会导致 shell 无法通过容器或服务、网络别名访问容器，进行通信
+ 2、通过容器名称、服务名称或网络别名访问容器的时候，需要注意命名，只能出现小写字母、数字、- 进行组合，不能出现其他字符。
	参考：https://en.wikipedia.org/wiki/Hostname
	



