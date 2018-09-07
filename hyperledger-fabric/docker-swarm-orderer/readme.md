# `Orderer` 和 `Kafka` 达成`Docker Swarm`集群

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

### Orderer 共识服务配置
orderer 在管理节点上固定分布位置
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
通过利用 `placement constraints` 分布约束策略，约束每个服务分布的节点位置，来控制Orderer服务访问的节点在同一个集群。而zookeeper可以分布在不同的机器上。
要让kafka和orderer服务在同一个节点上，在 orderer 和 kafka 服务上增加如下关键配置：
```yaml
placement:
    constraints:
      - node.role == manager
```
这样orderer服务就可以直接通过本机的kafka进行通信完成共识排序。

完整代码如下：
```yaml

```

## `zookeeper - placement constraints` & `kafka - deploy mode: global`

## `deploy mode: global` 模式
也就是 Orderer 需要访问的kafka是global模式，在集群中的所有节点上都存在一组kafka集群服务。这样当前Orderer服务所在的机器上就可以直接链接本机的kafka集群。

