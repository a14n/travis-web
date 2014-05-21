Auth = Ember.Object.extend
  state:        "signed-out"
  receivingEnd: "#{location.protocol}//#{location.host}"

  init: ->
    window.addEventListener('message', (e) => @receiveMessage(e))

  endpoint: (->
    @container.lookup('application:main').config.api_endpoint
  ).property(),

  signOut: ->
    Travis.storage.removeItem('travis.user')
    Travis.storage.removeItem('travis.token')
    Travis.sessionStorage.clear()
    @set('state', 'signed-out')
    @set('user', undefined)
    if user = @get('currentUser')
      user.unload()
    @set('currentUser', null)
    if hooksTarget = @get('hooksTarget')
      hooksTarget.afterSignOut()

  signIn: (data) ->
    if data
      @autoSignIn(data)
    else
      @set('state', 'signing-in')
      url = "#{@get('endpoint')}/auth/post_message?origin=#{@receivingEnd}"
      $('<iframe id="auth-frame" />').hide().appendTo('body').attr('src', url)

  autoSignIn: (data) ->
    data ||= @userDataFrom(Travis.sessionStorage) || @userDataFrom(Travis.storage)
    @setData(data) if data

  userDataFrom: (storage) ->
    userJSON = storage.getItem('travis.user')
    user  = JSON.parse userJSON if userJSON?
    user  = user.user if user?.user
    token = storage.getItem('travis.token')
    if user && token && @validateUser(user)
      { user: user, token: token }
    else
      # console.log('dropping user, no token') if token?
      storage.removeItem('travis.user')
      storage.removeItem('travis.token')
      null

  validateUser: (user) ->
    @validateHas('id', user) && @validateHas('login', user) && @validateHas('token', user) && @validateHas('correct_scopes', user) && user.correct_scopes

  validateHas: (field, user) ->
    if user[field]
      true
    else
      # console.log("discarding user data, lacks #{field}")
      false

  setData: (data) ->
    @storeData(data, Travis.sessionStorage)
    @storeData(data, Travis.storage) unless @userDataFrom(Travis.storage)
    user = @loadUser(data.user)
    @set('currentUser', user)

    @set('state', 'signed-in')
    Travis.trigger('user:signed_in', data.user)
    # TODO: I would like to get rid of this dependency in the future
    if hooksTarget = @get('hooksTarget')
      hooksTarget.afterSignIn()

  refreshUserData: (user) ->
    Travis.ajax.get "/users/#{user.id}", (data) =>
      Travis.loadOrMerge(Travis.User, data.user)
      # if user is still signed in, update saved data
      if @get('signedIn')
        data.user.token = user.token
        @storeData(data, Travis.sessionStorage)
        @storeData(data, Travis.storage)
    , (data, status, xhr) =>
      @signOut() if xhr.status == 401

  signedIn: (->
    @get('state') == 'signed-in'
  ).property('state')

  signedOut: (->
    @get('state') == 'signed-out'
  ).property('state')

  signingIn: (->
    @get('state') == 'signing-in'
  ).property('state')

  storeData: (data, storage) ->
    storage.setItem('travis.token', data.token) if data.token
    storage.setItem('travis.user', JSON.stringify(data.user))

  loadUser: (user) ->
    Travis.loadOrMerge(Travis.User, user)
    user = Travis.User.find(user.id)
    user.get('permissions')
    user

  receiveMessage: (event) ->
    if event.origin == @expectedOrigin()
      if event.data == 'redirect'
        window.location = "#{@get('endpoint')}/auth/handshake?redirect_uri=#{location}"
      else if event.data.user?
        event.data.user.token = event.data.travis_token if event.data.travis_token
        @setData(event.data)

  expectedOrigin: ->
    endpoint = @get('endpoint')
    if endpoint[0] == '/' then @receivingEnd else endpoint

Ember.onLoad 'Ember.Application', (Application) ->
  Application.initializer
    name: "auth",

    initialize: (container, application) ->
      application.register 'auth:main', Auth

      application.inject('route', 'auth', 'auth:main')
      application.inject('controller', 'auth', 'auth:main')
      application.inject('application', 'auth', 'auth:main')
