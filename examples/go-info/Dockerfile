FROM golang:1.12.9-buster as builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY main.go .
RUN CGO_ENABLED=0 go build -ldflags="-s"

# NB we use the buster-slim (instead of scratch) image so we can enter the container to execute bash etc.
FROM debian:buster-slim
COPY --from=builder /app/go-info .
WORKDIR /
EXPOSE 8000
ENTRYPOINT ["/go-info"]
