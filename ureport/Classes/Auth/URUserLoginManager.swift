//
//  URSocialNetworkManager.swift
//  ureport
//
//  Created by Daniel Amaral on 20/08/15.
//  Copyright (c) 2015 ilhasoft. All rights reserved.
//

import UIKit
import Firebase
import FBSDKLoginKit
import FBSDKCoreKit
import Accounts
import Social

protocol URUserLoginManagerDelegate {
    func userHasLoggedInGoogle(_ user:URUser)
}

class URUserLoginManager: NSObject, GIDSignInDelegate, GIDSignInUIDelegate {

    //MARK: Login Methods

    var loginViewController:UIViewController?
    var delegate:URUserLoginManagerDelegate?
    var googleSignIn: GIDSignIn!

    override init() {
        super.init()
        self.googleSignIn = GIDSignIn.sharedInstance()
        self.googleSignIn.delegate = self
        self.googleSignIn.uiDelegate = self
    }

    class func logoutFromSocialNetwork() {
        GIDSignIn.sharedInstance().disconnect()
        FBSDKLoginManager().logOut()
        //URFireBaseManager.sharedLoginInstance().unauth()
    }

    class func loginWithFacebook(_ viewController:UIViewController, completion:@escaping (URUser?) -> Void ) {
        let login = FBSDKLoginManager()
        login.logIn(withReadPermissions: ["email","user_birthday"], from: viewController) { (FBSDKLoginManagerLoginResult, error) -> Void in
            if error != nil {
                print(error!)
                completion(nil)
            }
            else {
                if (FBSDKLoginManagerLoginResult?.isCancelled)! {
                    completion(nil)
                } else {
                    if FBSDKAccessToken.current() != nil {
                        URFireBaseManager.authUserWithFacebook(token: FBSDKAccessToken.current().tokenString, completion: { (user) in
                            completion(user)
                        })
                    }
                }
            }
        }
    }

    class func loginWithTwitter(_ completion:@escaping (URUser?) ->Void ) {
        let accountStore = ACAccountStore()
        let accountType  = accountStore.accountType(withAccountTypeIdentifier: ACAccountTypeIdentifierTwitter)

        accountStore.requestAccessToAccounts(with: accountType, options: nil, completion: {success, error in
            if let twitterAccount = accountStore.accounts(with: accountType).first as? ACAccount {
                var properties = twitterAccount.dictionaryWithValues(forKeys: ["properties"])
                let details = (properties["properties"] as! NSDictionary)
                print("user_id  =  \(details["user_id"] as! String)")
                URTwitterAuthHelper.getAccessTokenKeyAndTokenSecret(twitterAccount, completion: { (tokenKey, tokenSecret) in
                    guard let _ = tokenKey else {
                        completion(nil)
                        return
                    }
                    URFireBaseManager.authUserWithTwitter(userId:details["user_id"] as! String, authToken:tokenKey!, authTokenSecret: tokenSecret!, completion: { (user) in
                        completion(user)
                    })
                })
            } else {
                completion(nil)
            }
        })
    }

    //MARK: GoogleSigninDelegate

    func loginWithGoogle(_ viewController:UIViewController) {
        googleSignIn.signIn()
    }

    func sign(_ signIn: GIDSignIn!, present viewController: UIViewController!) {
        self.loginViewController!.present(viewController, animated: true, completion: nil)
    }

    public func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser!, withError error: Error!) {
        if error != nil {
            print(error)
        }else{
            URFireBaseManager.authUserWithGoogle(token: user.authentication.accessToken, completion: { (user) in
                if self.delegate != nil {
                    self.delegate?.userHasLoggedInGoogle(user!)
                }
            })
    
        }
    }

    //MARK: Auth Methods

    class func login(_ email:String,password:String, completion:@escaping (Error?, Bool) -> Void) {
        URFireBaseManager.authUserWithPassword(email: email, password: password) { (user,error) in
            if let error = error {
                switch (error) {
                case URFireBaseManagerAuthError.invalidUser:
                    completion(error, false)
                case URFireBaseManagerAuthError.invalidEmail:
                    completion(error, false)
                default:
                    break
                }
            }else if let user = user {
                URLoginViewController.updateUserDataInRapidPro(user)
                URUserLoginManager.setUserAndCountryProgram(user)
                completion(nil,true)
            }
        }
    }

    class func resetPassword(_ email:String,completion:@escaping (Bool) -> Void) {
        URFireBaseManager.resetPassword(forUser: email, withCompletionBlock: { error in
            guard error == nil else {
                completion(false)
                return
            }
            completion(true)
        })
    }
    
    class func setLoggedUser(_ user:URUser) {
        URUserManager.checkIfUserIsMasterModerator(user.key) { (isMasterModerator) -> Void in
            if isMasterModerator == true {
                user.masterModerator = true
                URUser.setActiveUser(user)
            }else {
                URUserManager.checkIfUserIsCountryProgramModerator(user.key, completion: { (isModerator) -> Void in
                    if isModerator == true {
                        user.moderator = isModerator as NSNumber!
                    }
                    URUser.setActiveUser(user)
                })
                
            }
        }
    }

    class func setLoggedUserWithCompletion(_ user:URUser,mainCompletion:@escaping (_ finish:Bool) -> Void) {
        URUserManager.checkIfUserIsMasterModerator(user.key) { (isMasterModerator) -> Void in
            if isMasterModerator == true {
                user.masterModerator = true
                URUser.setActiveUser(user)
                mainCompletion(true)
            } else {
                URUserManager.checkIfUserIsCountryProgramModerator(user.key, completion: { (isModerator) -> Void in
                    if isModerator == true {
                        user.moderator = isModerator as NSNumber!
                    }
                    
                    URUser.setActiveUser(user)
                    mainCompletion(true)
                })
                
            }
        }
    }

    class func setUserAndCountryProgram(_ user:URUser) {
        URUser.setActiveUser(user)
        URUserLoginManager.setLoggedUser(user)

        URCountryProgramManager.setActiveCountryProgram(URCountryProgramManager.getCountryProgramByCountry(URCountry(code: user.country!)))
        URNavigationManager.setupNavigationControllerWithMainViewController(URMainViewController())
    }

    class func getFacebookUserDataWithDictionary(_ dictionary:NSDictionary) -> URUser{
        let user = URUser()

        if let key = dictionary["uid"] as? String {
            user.key = key
        }
        user.nickname = (dictionary["displayName"] as! String).replacingOccurrences(of: " ", with: "", options: [], range: nil)
        user.email = dictionary["email"] as? String
        user.picture = dictionary["profileImageURL"] as? String
        user.gender = ((dictionary["cachedUserProfile"]! as AnyObject).object(forKey: "gender") as! String) == "male" ? URGender.Male : URGender.Female
        user.type = URType.Facebook

        return user
    }

    class func getTwitterUserDataWithDictionary(_ dictionary:NSDictionary) -> URUser{
        let user = URUser()

        if let key = dictionary["uid"] as? String {
            user.key = key
        }

        user.nickname = dictionary["username"] as? String
        user.email = dictionary["email"] as? String
        user.picture = dictionary["profileImageURL"] as? String
        user.type = URType.Twitter

        return user
    }

    class func getGoogleUserDataWithDictionary(_ dictionary:NSDictionary) -> URUser{
        let user = URUser()

        if let key = dictionary["uid"] as? String {
            user.key = key
        }
        user.nickname = (dictionary["displayName"] as! String).replacingOccurrences(of: " ", with: "", options: [], range: nil)
        user.email = dictionary["email"] as? String
        user.picture = dictionary["profileImageURL"] as? String
        user.type = URType.Google

        return user
    }
}
