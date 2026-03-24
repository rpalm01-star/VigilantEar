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

# 5. Generate a new SSH key
ssh-keygen -t ed25519 -C "robert@wingdingssocial.com"

# 6. Start the ssh-agent and add your key
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# 7. Display the key to copy into GitLab (Settings > SSH Keys)
cat ~/.ssh/id_ed25519.pub

# 8. Clone the repository
git clone git@github.com:rpalm01-star/VigilantEar.git
cd VigilantEar
