# `Orderer` 和 `Kafka` 完成 `Docker Swarm`集群

Orderer和Kafka 进行集群完成Orderer排序共识机制，是 Hyperledger Ledger 超级账本区块链中重要的一环。但在Orderer和Kafka进行集群中问题很多，遇到了各种困难。导致困难的主要原因是**Orderer不能通过IP地址**直接访问Kafka集群，只能通过**服务的名称**或服务对应的**网络别名**访问集群进行通信。就目前而言，我在实际应用测试中是这样的情况，不排除还有其他的方式。

下面演示 一个 Orderer 排序服务，如何完成4个kafka和3个zookeeper的集群方法。

## `configtx.xml` 环境配置
```yaml
Kafka:
    # Brokers: A list of Kafka brokers to which the orderer connects. Edit
    # this list to identify the brokers of the ordering service.
    # NOTE: Use IP:port notation.
    Brokers:
      - "kafka0:9092"
      - "kafka1:9092"
      - "kafka2:9092"
      - "kafka3:9092"
```

在通过配置host情况下没有成功，kafka服务无法访问
```yaml
 Kafka:
    Brokers:
      #- "192.168.33.71:9092"
      #- "192.168.33.72:9092"
      # port host 模式下
      # 本机orderer节点不能直接通过ip地址访问本机的kafka
      # orderer 可以通过kafka2 服务名称访问，但不能通讯提示host找不到或者不能路由
      # kafka2 = 192.168.33.73 ip
      #- "kafka2:9092"
      #- "192.168.33.74:9092"
```

### `Orderer` 共识服务配置
`orderer` 在管理节点上固定分布位置
```yaml
$ cat docker-swarm-orderer.yaml

version: '3.6'

#-----------------------------------------------------------------------------------
# orderer networks yaml
#-----------------------------------------------------------------------------------
networks:
  net:
    external:
      name: orderer-zk-net

#-----------------------------------------------------------------------------------
# kafka & zookeeper service yaml
#-----------------------------------------------------------------------------------
services:
  orderer:
    container_name: orderer
    command: orderer
    hostname: orderer.example.com
    environment:
      GRPC_TRACE: all=true,
      GRPC_VERBOSITY: debug
      ORDERER_GENERAL_AUTHENTICATION_TIMEWINDOW: 3600s
      ORDERER_GENERAL_GENESISFILE: /etc/hyperledger/configtx/genesis.block
      ORDERER_GENERAL_GENESISMETHOD: file
      ORDERER_GENERAL_LISTENADDRESS: 0.0.0.0
      ORDERER_GENERAL_LOCALMSPDIR: /etc/hyperledger/msp/orderer/msp
      ORDERER_GENERAL_LOCALMSPID: OrdererMSP
      ORDERER_GENERAL_LOGLEVEL: debug
      ORDERER_GENERAL_TLS_CERTIFICATE: /etc/hyperledger/msp/orderer/tls/server.crt
      ORDERER_GENERAL_TLS_CLIENTAUTHREQUIRED: "false"
      ORDERER_GENERAL_TLS_CLIENTROOTCAS: '[/etc/hyperledger/msp/peerOrg1/msp/tlscacerts/tlsca.org1.foo.com-cert.pem,/etc/hyperledger/msp/peerOrg2/msp/tlscacerts/tlsca.org2.bar.com-cert.pem]'
      ORDERER_GENERAL_TLS_ENABLED: "false"
      ORDERER_GENERAL_TLS_PRIVATEKEY: /etc/hyperledger/msp/orderer/tls/server.key
      ORDERER_GENERAL_TLS_ROOTCAS: '[/etc/hyperledger/msp/orderer/tls/ca.crt]'
      
      ORDERER_KAFKA_RETRY_SHORTINTERVAL: 1s
      ORDERER_KAFKA_RETRY_SHORTTOTAL: 30s
      ORDERER_KAFKA_VERBOSE: "true"
    image: hyperledger/fabric-orderer:x86_64-1.1.0
    ports:
    - published: 7050
      target: 7050
    volumes:
    - ./fabric-configs/v1.1/channel-artifacts:/etc/hyperledger/configtx:ro
    - ./fabric-configs/v1.1/crypto-config/ordererOrganizations/simple.com/orderers/orderer.simple.com:/etc/hyperledger/msp/orderer:ro
    - ./fabric-configs/v1.1/crypto-config/peerOrganizations/org1.foo.com/peers/peer0.org1.foo.com:/etc/hyperledger/msp/peerOrg1:ro
    - ./fabric-configs/v1.1/crypto-config/peerOrganizations/org2.bar.com/peers/peer0.org2.bar.com:/etc/hyperledger/msp/peerOrg2:ro
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric
    deploy:
      placement:
        constraints:
        - node.role == manager
      resources:
        limits:
          cpus: '0.5'
      restart_policy:
        condition: on-failure
    networks:
      net:
        aliases:
        - orderer.example.com
```

## 方案1：`kafka` 和 `Orderer` 同节点，`zookeeper` 分布不同节点
> 利用 `placement constraints` 分布约束模式，让 `zookeeper` 分布在不同机器，`kafka` 和 `Orderer` 同一个机器。

通过利用 `placement constraints` 分布约束策略，约束每个服务分布的节点位置，来控制`Orderer`服务访问的节点在同一个集群。而`zookeeper`可以分布在不同的机器上。
要让`kafka`和`orderer`服务在同一个节点上，在 `orderer` 和 `kafka` 服务上增加如下关键配置：
```yaml
placement:
    constraints:
      - node.role == manager
```
这样`orderer`服务就可以直接通过本机的`kafka`进行通信完成共识排序。

完整代码如下：
```yaml
version: '3.6'

#-----------------------------------------------------------------------------------
# base config yaml
#-----------------------------------------------------------------------------------
x-hosts: &hosts
  - "dev-010:192.168.33.71"
  - "dev-020:192.168.33.72"
  - "dev-030:192.168.33.73"
  - "dev-040:192.168.33.74"
  
#-----------------------------------------------------------------------------------
# base service yaml
#-----------------------------------------------------------------------------------
x-base-services:
  zookeeper: &zookeeper-base
    image: hyperledger/fabric-zookeeper${IMAGE_TAG_FABRIC_ZOOKEEPER}
    ports:
      - target: 2181
        published: 2181
        protocol: tcp
        mode: host
      - target: 2888
        published: 2888
        protocol: tcp
        mode: host
      - target: 3888
        published: 3888
        protocol: tcp
        mode: host
    deploy: &zookeeper-deploy-common
      restart_policy:
        condition: on-failure
    extra_hosts: *hosts

  kafka: &kafka-base
    image: hyperledger/fabric-kafka${IMAGE_TAG_FABRIC_KAFKA}
    environment: &kafka-env-common
      KAFKA_MESSAGE_MAX_BYTES: 103809024 # 99 * 1024 * 1024 B
      KAFKA_REPLICA_FETCH_MAX_BYTES: 103809024 # 99 * 1024 * 1024 B
      KAFKA_UNCLEAN_LEADER_ELECTION_ENABLE: "false"
      KAFKA_MIN_INSYNC_REPLICAS: 2
      KAFKA_DEFAULT_REPLICATION_FACTOR: 3
      KAFKA_LOG_RETENTION_MS: -1
      KAFKA_ZOOKEEPER_CONNECT: dev-010:2181,dev-020:2181,dev-040:2181

      #zookeeper.connection.timeout.ms
      KAFKA_ZOOKEEPER_CONNECTION_TIMEOUT_MS: 30000
      #zookeeper.session.timeout.ms
      KAFKA_ZOOKEEPER_SESSION_TIMEOUT_MS: 30000
    expose:
      - 9092
    deploy: &kafka-deploy-common
      restart_policy:
        condition: on-failure
      placement:
        constraints:
          - node.role == manager
    extra_hosts: *hosts

#-----------------------------------------------------------------------------------
# kafka & zookeeper networks yaml
#-----------------------------------------------------------------------------------
networks:
  net:
    external:
      name: orderer-zk-net
    
#-----------------------------------------------------------------------------------
# zookeeper service yaml
#-----------------------------------------------------------------------------------
services:
  zookeeper0:
    hostname: zookeeper0.example.com
    <<: *zookeeper-base
    deploy:
      <<: *zookeeper-deploy-common
      placement:
        constraints:
          - node.hostname == dev-010
    environment:
      ZOO_MY_ID: 1
      ZOO_SERVERS: server.1=0.0.0.0:2888:3888 server.2=dev-020:2888:3888 server.3=dev-040:2888:3888
    networks:
      net:
        aliases:
        - zookeeper0.example.com

  zookeeper1:
    hostname: zookeeper1.example.com
    <<: *zookeeper-base
    deploy:
      <<: *zookeeper-deploy-common
      placement:
        constraints:
          - node.hostname == dev-020
    environment:
      ZOO_MY_ID: 2
      ZOO_SERVERS: server.1=dev-010:2888:3888 server.2=0.0.0.0:2888:3888 server.3=dev-040:2888:3888
    networks:
      net:
        aliases:
        - zookeeper1.example.com

  zookeeper2:
    hostname: zookeeper2.example.com
    <<: *zookeeper-base
    deploy:
      <<: *zookeeper-deploy-common
      placement:
        constraints:
          - node.hostname == dev-040
    environment:
      ZOO_MY_ID: 3  
      ZOO_SERVERS: server.1=dev-010:2888:3888 server.2=dev-020:2888:3888 server.3=0.0.0.0:2888:3888
    networks:
      net:
        aliases:
        - zookeeper2.example.com

#-----------------------------------------------------------------------------------
# kafka service yaml
#-----------------------------------------------------------------------------------
  kafka0:
    hostname: kafka0.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 0
    networks:
      net:
        aliases:
        - kafka0.example.com
  
  kafka1:
    hostname: kafka1.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 1
    networks:
      net:
        aliases:
        - kafka1.example.com
 
  kafka2:
    hostname: kafka2.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 2
    networks:
      net:
        aliases:
        - kafka2.example.com
 
  kafka3:
    hostname: kafka3.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 3
    networks:
      net:
        aliases:
        - kafka3.example.com
```

## 方案2：`kafka` 和 `Orderer` 、`zookeeper` 都分布在同一个节点
> 利用 `placement constraints` 分布约束模式，让 `zookeeper`、`kafka` 和 `Orderer` 分布在同一个机器。

此模式可以不再`docker swarm`下进行`stack`服务编排部署，可以直接通过 `docker-compose` 进行部署单个集群服务，而不进行`swarm`负载均衡服务。
参考代码：docker-compose-zk.yaml

完整代码如下：
```yaml
version: '3.6'

#-----------------------------------------------------------------------------------
# base service yaml
#-----------------------------------------------------------------------------------
x-base-services:
  zookeeper: &zookeeper-base
    image: hyperledger/fabric-zookeeper${IMAGE_TAG_FABRIC_ZOOKEEPER}
    expose:
      - 2181
      - 2888
      - 3888
    deploy: &zookeeper-deploy-common
      restart_policy:
        condition: on-failure
      placement:
        constraints:
          - node.role == manager

  kafka: &kafka-base
    image: hyperledger/fabric-kafka${IMAGE_TAG_FABRIC_KAFKA}
    environment: &kafka-env-common
      KAFKA_MESSAGE_MAX_BYTES: 103809024 # 99 * 1024 * 1024 B
      KAFKA_REPLICA_FETCH_MAX_BYTES: 103809024 # 99 * 1024 * 1024 B
      KAFKA_UNCLEAN_LEADER_ELECTION_ENABLE: "false"
      KAFKA_MIN_INSYNC_REPLICAS: 2
      KAFKA_DEFAULT_REPLICATION_FACTOR: 3
      KAFKA_LOG_RETENTION_MS: -1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper0:2181,zookeeper1:2181,zookeeper2:2181

      #zookeeper.connection.timeout.ms
      KAFKA_ZOOKEEPER_CONNECTION_TIMEOUT_MS: 30000
      #zookeeper.session.timeout.ms
      KAFKA_ZOOKEEPER_SESSION_TIMEOUT_MS: 30000
    expose:
      - 9092
    deploy: &kafka-deploy-common
      restart_policy:
        condition: on-failure
      placement:
        constraints:
          - node.role == manager

#-----------------------------------------------------------------------------------
# kafka & zookeeper networks yaml
#-----------------------------------------------------------------------------------
networks:
  net:
    external:
      name: orderer-zk-net
    
#-----------------------------------------------------------------------------------
# kafka & zookeeper service yaml
#-----------------------------------------------------------------------------------
services:
  zookeeper0:
    hostname: zookeeper0.example.com
    <<: *zookeeper-base
    deploy:
      <<: *zookeeper-deploy-common
    environment:
      ZOO_MY_ID: 1
      ZOO_SERVERS: server.1=zookeeper0:2888:3888 server.2=zookeeper1:2888:3888 server.3=zookeeper2:2888:3888
    networks:
      net:
        aliases:
        - zookeeper0.example.com

  zookeeper1:
    hostname: zookeeper1.example.com
    <<: *zookeeper-base
    deploy:
      <<: *zookeeper-deploy-common
    environment:
      ZOO_MY_ID: 2
      ZOO_SERVERS: server.1=zookeeper0:2888:3888 server.2=zookeeper1:2888:3888 server.3=zookeeper2:2888:3888
    networks:
      net:
        aliases:
        - zookeeper1.example.com

  zookeeper2:
    hostname: zookeeper2.example.com
    <<: *zookeeper-base
    deploy:
      <<: *zookeeper-deploy-common
    environment:
      ZOO_MY_ID: 3  
      ZOO_SERVERS: server.1=zookeeper0:2888:3888 server.2=zookeeper1:2888:3888 server.3=zookeeper2:2888:3888
    networks:
      net:
        aliases:
        - zookeeper2.example.com

  kafka0:
    hostname: kafka0.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 0
    networks:
      net:
        aliases:
        - kafka0.example.com
  
  kafka1:
    hostname: kafka1.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 1
    networks:
      net:
        aliases:
        - kafka1.example.com
 
  kafka2:
    hostname: kafka2.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 2
    networks:
      net:
        aliases:
        - kafka2.example.com
 
  kafka3:
    hostname: kafka3.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 3
    networks:
      net:
        aliases:
        - kafka3.example.com
```

## 方案3：`kafka` 和 `zookeeper` 全局分布，都分布同节点
> 利用 `deploy mode: global` 全局副本模式 将 `zookeeper` 和 `kafka` 分布在每台机器上进行集群，每台集群上都有一组`kafka`集群和`zookeeper`集群，每台机器上的`kafka`服务都链接到本机上的`zookeeper`服务进行自动服务发现与注册。

要让`kafka`服务在每个节点上，在 `kafka` 服务上增加如下关键配置：
```yaml
deploy: 
  mode: global
```


完整代码如下：
```yaml
version: '3.6'

#-----------------------------------------------------------------------------------
# base service yaml
#-----------------------------------------------------------------------------------
x-base-services:
  zookeeper: &zookeeper-base
    image: hyperledger/fabric-zookeeper${IMAGE_TAG_FABRIC_ZOOKEEPER}
    expose:
      - 2181
      - 2888
      - 3888
    deploy: &zookeeper-deploy-common
      mode: global
      restart_policy:
        condition: on-failure

  kafka: &kafka-base
    image: hyperledger/fabric-kafka${IMAGE_TAG_FABRIC_KAFKA}
    environment: &kafka-env-common
      KAFKA_MESSAGE_MAX_BYTES: 103809024 # 99 * 1024 * 1024 B
      KAFKA_REPLICA_FETCH_MAX_BYTES: 103809024 # 99 * 1024 * 1024 B
      KAFKA_UNCLEAN_LEADER_ELECTION_ENABLE: "false"
      KAFKA_MIN_INSYNC_REPLICAS: 2
      KAFKA_DEFAULT_REPLICATION_FACTOR: 3
      KAFKA_LOG_RETENTION_MS: -1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper0:2181,zookeeper1:2181,zookeeper2:2181

      #zookeeper.connection.timeout.ms
      KAFKA_ZOOKEEPER_CONNECTION_TIMEOUT_MS: 30000
      #zookeeper.session.timeout.ms
      KAFKA_ZOOKEEPER_SESSION_TIMEOUT_MS: 30000
    expose:
      - 9092
    deploy: &kafka-deploy-common
      mode: global
      restart_policy:
        condition: on-failure

#-----------------------------------------------------------------------------------
# kafka & zookeeper networks yaml
#-----------------------------------------------------------------------------------
networks:
  net:
    external:
      name: orderer-zk-net
    
#-----------------------------------------------------------------------------------
# kafka & zookeeper service yaml
#-----------------------------------------------------------------------------------
services:
  zookeeper0:
    hostname: zookeeper0.example.com
    <<: *zookeeper-base
    deploy:
      <<: *zookeeper-deploy-common
    environment:
      ZOO_MY_ID: 1
      ZOO_SERVERS: server.1=zookeeper0:2888:3888 server.2=zookeeper1:2888:3888 server.3=zookeeper2:2888:3888
    networks:
      net:
        aliases:
        - zookeeper0.example.com

  zookeeper1:
    hostname: zookeeper1.example.com
    <<: *zookeeper-base
    deploy:
      <<: *zookeeper-deploy-common
    environment:
      ZOO_MY_ID: 2
      ZOO_SERVERS: server.1=zookeeper0:2888:3888 server.2=zookeeper1:2888:3888 server.3=zookeeper2:2888:3888
    networks:
      net:
        aliases:
        - zookeeper1.example.com

  zookeeper2:
    hostname: zookeeper2.example.com
    <<: *zookeeper-base
    deploy:
      <<: *zookeeper-deploy-common
    environment:
      ZOO_MY_ID: 3  
      ZOO_SERVERS: server.1=zookeeper0:2888:3888 server.2=zookeeper1:2888:3888 server.3=zookeeper2:2888:3888
    networks:
      net:
        aliases:
        - zookeeper2.example.com

  kafka0:
    hostname: kafka0.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 0
    networks:
      net:
        aliases:
        - kafka0.example.com
  
  kafka1:
    hostname: kafka1.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 1
    networks:
      net:
        aliases:
        - kafka1.example.com
 
  kafka2:
    hostname: kafka2.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 2
    networks:
      net:
        aliases:
        - kafka2.example.com
 
  kafka3:
    hostname: kafka3.example.com
    <<: *kafka-base
    deploy:
      <<: *kafka-deploy-common
    environment:
      <<: *kafka-env-common
      KAFKA_BROKER_ID: 3
    networks:
      net:
        aliases:
        - kafka3.example.com
```

