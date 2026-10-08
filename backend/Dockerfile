FROM golang:1.27.1-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 go build -trimpath -o /server ./cmd/server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /server /usr/local/bin/server
USER 65532:65532
ENV APP_ENV=production HOST=0.0.0.0 PORT=8080
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/server"]
