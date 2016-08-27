#import "ArtsyAuthentication.h"
#import "ArtsyAuthentication+Private.h"
#import "ArtsyNetworkOperator.h"
#import "ArtsyToken.h"
#import "ArtsyAuthenticationRouter.h"
#import <ISO8601DateFormatter/ISO8601DateFormatter.h>

NSString* const ArtsyOAuthTokenKey = @"access_token";
NSString* const ArtsyOAuthExpiryKey = @"expires_in";
NSString* const ArtsyXAppTokenKey = @"xapp_token";

NSString* const ArtsyAuthenticationErrorDomain = @"ArtsyAuthenticationErrorDomain";

@interface ArtsyAuthentication()

@property (nonatomic, strong) ArtsyNetworkOperator *networkOperator;

@end

@implementation ArtsyAuthentication

- (instancetype)initWithClientID:(NSString *)clientID
                    clientSecret:(NSString *)clientSecret;
{
    self = [super init];
    if (!self) return nil;

    _router = [[ArtsyAuthenticationRouter alloc] initWithClientID:clientID clientSecret:clientSecret];
    _networkOperator = [[ArtsyNetworkOperator alloc] init];

    return self;
}

#pragma mark - Public API

- (void)getWeekLongXAppTrialToken:(ArtsyAuthenticationCallback)completion;
{
    __weak __typeof(self) weakSelf = self;

    NSURLRequest *request = [self.router requestForXapp];
    [self.networkOperator JSONTaskWithRequest:request success:^(NSURLRequest *_, NSHTTPURLResponse *__, id JSON) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;

        NSDate *date = [[[ISO8601DateFormatter alloc] init] dateFromString:JSON[@"expires_in"]];
        ArtsyToken *token = [[ArtsyToken alloc] initWithToken:JSON[ArtsyXAppTokenKey] expirationDate:date];

        strongSelf.router.xappToken = token;

        completion(token, nil);
    } failure:^(NSURLRequest *_, NSHTTPURLResponse *response, NSError *error, id JSON) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;

        [strongSelf findErrorsInResponse:response error:&error dict:JSON];
        completion(JSON, error);
    }];
}

- (void)logInWithEmail:(NSString *)email
              password:(NSString *)password
            completion:(ArtsyAuthenticationCallback)completion;
{
    __weak __typeof(self) weakSelf = self;

    NSURLRequest *request = [self.router requestForAuthWithEmail:email password:password];
    [self.networkOperator JSONTaskWithRequest:request success:^(NSURLRequest *_, NSHTTPURLResponse *__, id JSON) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;

        NSDate *date = [[[ISO8601DateFormatter alloc] init] dateFromString:JSON[@"expires_in"]];
        ArtsyToken *token = [[ArtsyToken alloc] initWithToken:JSON[ArtsyOAuthTokenKey] expirationDate:date];

        [strongSelf callback:token error:nil completion:completion];
    } failure:^(NSURLRequest *_, NSHTTPURLResponse *response, NSError *error, id JSON) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;

        [strongSelf findErrorsInResponse:response error:&error dict:JSON];
        [strongSelf callback:nil error:error completion:completion];
    }];
}

- (void)logInAndFetchUserDetailsWithEmail:(NSString *)email
                                 password:(NSString *)password
                               completion:(ArtsyAuthenticationWithUserDetailsCallback)completion;
{
    __weak __typeof(self) weakSelf = self;

    [self logInWithEmail:email password:password completion:^(ArtsyToken *token, NSError *error) {
        if (error) {
            completion(token, nil, error);
        } else {
            __strong __typeof(weakSelf) strongSelf = weakSelf;

            if (strongSelf) {
              NSURLRequest *request = [strongSelf.router requestForUserDetails];
              [strongSelf.networkOperator JSONTaskWithRequest:request success:^(NSURLRequest *_, NSHTTPURLResponse *__, id JSON) {
                completion(token, JSON, nil);
              } failure:^(NSURLRequest *_, NSHTTPURLResponse *response, NSError *error, id JSON) {
                [weakSelf findErrorsInResponse:response error:&error dict:JSON];
                completion(token, JSON, error);
              }];
            }
        }
    }];
}

- (void)createUserWithEmail:(NSString *)email
                       name:(NSString *)name
                   password:(NSString *)password
                 completion:(void (^)(NSDictionary *newUserDictionary, NSError *error))completion;
{
    __weak __typeof(self) weakSelf = self;

    NSURLRequest *request = [self.router requestForCreateNewUserwithEmail:email name:name password:password];
    [self.networkOperator JSONTaskWithRequest:request success:^(NSURLRequest *_, NSHTTPURLResponse *__, id JSON) {
        completion(JSON, nil);
    } failure:^(NSURLRequest *_, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [weakSelf findErrorsInResponse:response error:&error dict:JSON];
        completion(JSON, error);
    }];
}

#pragma mark - Request Management

- (void)findErrorsInResponse:(NSHTTPURLResponse *)response
                       error:(NSError **)error
                        dict:(NSDictionary *)dict;
{
    if (*error) return;
    if (response.statusCode != 500) {
        *error = [NSError errorWithDomain:@"net.artsy" code:response.statusCode userInfo:dict];
    }
}

- (void)logout;
{
    self.router.authToken = nil;
}

@end
