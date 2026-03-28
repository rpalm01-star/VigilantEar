# 1. CLONE THE PROJECT
git clone git@github.com:rpalm01-star/VigilantEar.git
cd VigilantEar

# 2. INSTALL GOOGLE CLOUD SDK
# If you haven't installed Homebrew yet:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install --cask google-cloud-sdk

# 3. CONFIGURE GCP IDENTITY
gcloud auth login robert@wingdingssocial.com
gcloud config set project vigilantear-research

# 4. SETUP XCODE ENVIRONMENT
# Open the project in Xcode 26
open com.rpalm.vigilantEar/VigilantEar.xcodeproj
