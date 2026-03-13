# Add AWS CLI installed by this buildpack to PATH.
# This buildpack installs into a CNB layer at $LAYERS_DIR/awscli.
export PATH="$LAYERS_DIR/awscli/bin:$PATH"
