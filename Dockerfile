FROM ballerina/ballerina:latest
COPY . /home/APIS_UMT
EXPOSE 5000
WORKDIR /home/APIS_UMT
USER root
RUN adduser -u 10001 -S appuser && chown -hR 10001 /home/APIS_UMT && \
    chmod -R 755 /home/APIS_UMT
USER 10001
RUN bal persist generate
CMD bal run 