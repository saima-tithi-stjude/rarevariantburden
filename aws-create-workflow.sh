aws omics create-workflow \
    --name cocorv-nf \
    --region us-east-1 \
    --definition-zip fileb://rarevariantburden.zip \
    --parameter-template file://rarevariantburden/aws.parameter.template.json \
    --container-registry-map file://rarevariantburden/aws.container-registry-map.json \
    --readme-markdown file://rarevariantburden/README.md \
    --engine NEXTFLOW \
    --no-verify-ssl
