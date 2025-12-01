# ---------- Stage 1: Build ----------
FROM golang:1.25 AS build-stage

# Set working directory
WORKDIR /app

# Copy go.mod and go.sum first to leverage caching
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the source code
COPY *.go ./

# Build the Go binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o product-search .

# ---------- Stage 2: Run ----------
FROM alpine:latest

# Install CA certificates (needed for HTTPS requests)
RUN apk add --no-cache ca-certificates

# Set working directory
WORKDIR /app

# Copy binary from builder
COPY --from=build-stage /app/product-search .

# Expose port
EXPOSE 8080

# Run the application
CMD ["./product-search"]