FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    less \
    groff \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 (supports both x86_64 and ARM64 / Apple Silicon)
RUN ARCH=$(uname -m) \
    && if [ "$ARCH" = "aarch64" ]; then \
         AWS_ZIP="awscli-exe-linux-aarch64.zip"; \
       else \
         AWS_ZIP="awscli-exe-linux-x86_64.zip"; \
       fi \
    && curl -fsSL "https://awscli.amazonaws.com/$AWS_ZIP" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Install boto3
RUN pip install --no-cache-dir boto3

WORKDIR /lab

# Copy all lab scripts into the image
COPY *.sh ./

# Strip Windows carriage returns and make scripts executable
RUN sed -i 's/\r//' *.sh && chmod +x *.sh

CMD ["/bin/bash"]
