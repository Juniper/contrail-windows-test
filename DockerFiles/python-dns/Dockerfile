# escape=`
FROM python:3.7

COPY dnslib-0.9.7.tar.gz C:\
RUN pip install C:\dnslib-0.9.7.tar.gz
RUN mkdir C:\zones
COPY zones C:\zones
COPY dnserver.py C:\
EXPOSE 53/tcp
EXPOSE 53/udp
CMD py C:\dnserver.py
