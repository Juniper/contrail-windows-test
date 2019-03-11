FROM python:3.7

EXPOSE 8080

WORKDIR C:/

# By default, RUN behaves as if the /U parameter was passed to cmd.
# This results in UTF-16 encoded files.
# To prevent this, /A (ansi) flag is passed explicitely.
RUN ["cmd", "/A", "/C", "echo Hello, Contrail! > index.html"]
ENTRYPOINT python -m http.server 8080
