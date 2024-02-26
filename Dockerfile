FROM ballerina/jvm-runtime:2.0
COPY . /APIS_UMT
EXPOSE 5000

RUN ["bal", "pack"]
RUN ["bal", "persist", "generate"]
RUN ["bal", "run"]