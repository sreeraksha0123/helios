FROM golang:1.22-bookworm AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download || true
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/demo-api .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/demo-api /demo-api
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/demo-api"]
