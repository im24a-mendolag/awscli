FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    less \
    groff \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Install boto3
RUN pip install --no-cache-dir boto3

WORKDIR /lab

# Copy all lab scripts into the image
COPY *.sh ./

# Make scripts executable
RUN chmod +x *.sh

CMD ["/bin/bash"]
