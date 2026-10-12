# gRPC server (server.py) is added once the ExtMCP proto is vendored at the pinned agentgateway tag.
FROM python:3.13-slim
RUN useradd --uid 10001 --no-create-home app
WORKDIR /app
COPY rules.py .
USER 10001
EXPOSE 4445
CMD ["python", "-c", "import rules; print('ext-mcp: rules loaded; server.py pending proto')"]
