FROM golang:1.22-bookworm AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download || true
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/demo-worker .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/demo-worker /demo-worker
USER nonroot:nonroot
EXPOSE 8081
ENTRYPOINT ["/demo-worker"]
