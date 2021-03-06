//
//  MailingListService.swift
//  MPMailingListService
//
//  Created by Matias Piipari on 09/09/2016.
//  Copyright © 2016 Matias Piipari & Co. All rights reserved.
//

import Foundation
import ChimpKit

@objc public enum MailingListType:UInt {
    case Newsletter = 1 // TODO: model this as a freeform value if requested.
}

@objc public protocol MailingListServiceDataSource {
    func APIKey(mailingListService service: MailingListService) -> String
    func listIdentifier(mailingListService service: MailingListService, listType:MailingListType) -> String
}

public typealias MailingListServiceSignupCompletionBlock = (error:ErrorType?) -> Void

@objc public class MailingListService: NSObject {
    
    public static let ErrorDomain = "MailingListServiceErrorDomain"
    
    public enum Error:ErrorType {
        case UnexpectedResponse
        case AlreadySignedUp
        case EmptyResponse
        case ResponseDataNotJSON(NSData?)
        case ErrorCodeNotNumber([String:AnyObject])
        
        public var code:Int {
            switch self {
            case .AlreadySignedUp: return 1
            case .EmptyResponse: return 2
            case .ErrorCodeNotNumber(_): return 3
            case .ResponseDataNotJSON(_): return 5
            case .UnexpectedResponse: return 6
            }
        }
        
        public var presentableDescription: String {
            switch self {
            
            case .AlreadySignedUp:
                return "Email address is already signed up."
            
            case .EmptyResponse:
                return "Empty response from server. Please contact customer support if this persists."
            
            case .UnexpectedResponse,
                 .ResponseDataNotJSON(_),
                 .ErrorCodeNotNumber(_):
                return "Unexpected response from server. Please contact customer support if this persists."
            }
        }
        
        public var presentableRecoverySuggestion: String {
            switch self {
                
            case .AlreadySignedUp:
                return "Email address looks to be already signed up.\nPlease contact support if you believe this is an error."
                
            case .EmptyResponse:
                return "Empty response from server.\nPlease contact support if this persists."
                
            case .UnexpectedResponse,
                 .ResponseDataNotJSON(_),
                 .ErrorCodeNotNumber(_):
                return "Unexpected response from server.\nPlease contact support if this persists."
            }
        }
        
        public var presentableRepresentation:NSError {
            return NSError(domain: ErrorDomain,
                           code: self.code,
                           userInfo: [ NSLocalizedDescriptionKey: self.presentableDescription,
                            NSLocalizedRecoverySuggestionErrorKey: self.presentableRecoverySuggestion ])
        }
    }
    
    private(set) public weak var dataSource:MailingListServiceDataSource?
    private let chimpKit:ChimpKit
    
    public init(dataSource:MailingListServiceDataSource) {
        self.dataSource = dataSource
        self.chimpKit = ChimpKit()
        
        super.init()
        
        self.chimpKit.apiKey = self.dataSource?.APIKey(mailingListService: self)
    }
    
    public func signUp(emailAddress address:String,
                                    listType:MailingListType,
                                    completionHandler: MailingListServiceSignupCompletionBlock) {
        
        guard let listID = self.dataSource?.listIdentifier(mailingListService: self, listType: listType) else {
            preconditionFailure("Missing data source")
        }
        
        
        let params:[NSObject:AnyObject] = ["id": listID, "email": ["email":address]]
        
        self.chimpKit.callApiMethod("lists/subscribe", withParams: params) { response, data, error in
            if let error = error {
                dispatch_async(dispatch_get_main_queue()) {
                    completionHandler(error:error)
                }
                return
            }
            
            guard let HTTPResponse = response as? NSHTTPURLResponse else {
                preconditionFailure("Response ought to be a HTTP response: \(response)")
            }
            
            let statusCode = HTTPResponse.statusCode
            if (200...299).contains(statusCode) {
                completionHandler(error:nil)
                return
            }
            
            do {
                guard let respData = data,
                      let dict = try NSJSONSerialization.JSONObjectWithData(respData,
                                                                            options: []) as? [String:AnyObject]
                    else {
                        completionHandler(error:Error.EmptyResponse.presentableRepresentation)
                        return
                }
                
                guard let codeNum = dict["code"] as? NSNumber else {
                    completionHandler(error:Error.ErrorCodeNotNumber(dict).presentableRepresentation)
                    return
                }
                
                if codeNum.integerValue == 214 {
                    completionHandler(error: Error.AlreadySignedUp.presentableRepresentation)
                }
            }
            catch {
                completionHandler(error:Error.ResponseDataNotJSON(data).presentableRepresentation)
            }
        }
    }
}

