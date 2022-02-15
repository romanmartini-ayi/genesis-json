FROM ubuntu:20.04
RUN apt -y update && apt -y install git make gcc g++ tree tar vim jq nmap

# Go v1.14
# https://dl.google.com/go/go1.14.2.linux-amd64.tar.gz
COPY go1.14.2.linux-amd64.tar.gz /go1.14.2.linux-amd64.tar.gz
RUN cat go1.14.2.linux-amd64.tar.gz | tar -xz -C /usr/local
ENV PATH=$PATH:/usr/local/go/bin

# Quorum tools
# https://github.com/Consensys/quorum.git
COPY quorum /quorum
WORKDIR /quorum
RUN make all && \
    cp /quorum/build/bin/* /usr/bin

# entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# BC root
RUN mkdir -p /Raft-Network
WORKDIR /Raft-Network

COPY genesis.json /docker-entrypoint-init/genesis.json

ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["tail_main"]