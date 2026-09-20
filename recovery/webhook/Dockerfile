FROM python:3.12-alpine

# docker-cli: the playbook shells out to `docker restart`.
# ansible-core: brings ansible-playbook plus the builtin modules we use
#   (command, pause, wait_for, uri, assert) — no extra collections needed.
RUN apk add --no-cache docker-cli \
    && pip install --no-cache-dir ansible-core==2.17.6

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
