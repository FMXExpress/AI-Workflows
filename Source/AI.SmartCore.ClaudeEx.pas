unit AI.SmartCore.ClaudeEx;

// TAIClaudeDriverEx - a fixed Claude driver for SmartCore.
//
// SmartCore's stock TAIClaudeDriver builds every /v1/messages body through
// TClaudeMessageRequest, whose constructor hardcodes top_k=250 (plus top_p
// and temperature) and whose serializer emits every public member. Claude 4
// family models reject the request outright:
//
//   invalid_request_error: `top_k` is deprecated for this model.
//
// There is no param to suppress it and the request build is buried in a
// closure - but TAIDriver.Chat is virtual, so this subclass overrides it and
// builds a MINIMAL body instead: model, max_tokens, messages, and an
// optional real 'system' field (SystemText). No sampling parameters at all -
// the provider's defaults apply, and Claude 4 models accept the request.
//
// Also defaults the anthropic-version header to the stable '2023-06-01' when
// the param is left empty (the stock driver sends it verbatim-empty and the
// API rejects that too).
//
// Everything else (models listing, streaming, files, batches, events,
// cancellation) is inherited unchanged. Drop this instead of TAIClaudeDriver.

interface

uses
  System.Classes,
  System.SysUtils,
  System.JSON,
  System.Net.HttpClient,
  SmartCoreAI.Types,
  SmartCoreAI.Consts,
  SmartCoreAI.Exceptions,
  SmartCoreAI.HttpClientConfig,
  SmartCoreAI.Driver.Claude;

type
  TAIClaudeDriverEx = class(TAIClaudeDriver)
  private
    FSystemText: string;
  public
    function Chat(const APrompt: string;
      const ACallback: IAIChatCallback): TGUID; override;
  published
    // Sent as the real Anthropic 'system' field (the stock driver has no
    // system support at all).
    property SystemText: string read FSystemText write FSystemText;
  end;

procedure Register;

implementation

const
  CDefaultAnthropicVersion = '2023-06-01';

function TAIClaudeDriverEx.Chat(const APrompt: string;
  const ACallback: IAIChatCallback): TGUID;
var
  LHttpClient: THTTPClient;
  LId: TGUID;
  LState: TAIRequestState;
  LParams: TAIClaudeParams;
begin
  LState := BeginRequest(LId);
  Result := LId;

  LParams := Params as TAIClaudeParams;
  if (LParams.APIKey = '') or (LParams.Model = '') or (APrompt = '') then
  begin
    DoErrorChat(ACallback, 'Claude driver needs APIKey, Model and a prompt.', nil);
    EndRequest(LId);
    Exit;
  end;

  LHttpClient := TAIHttpClientConfig.CreateClient(nil);
  Run(LState, LId, LHttpClient,
    procedure
    var
      LRoot, LMsg, LJSON: TJSONObject;
      LMessages, LContent: TJSONArray;
      LBody, LText, LRaw, LVersion: string;
      LResp: IHTTPResponse;
      LStream: TStringStream;
    begin
      InvokeEvent(procedure begin ACallback.DoBeforeRequest end);

      // Minimal body: no temperature/top_k/top_p - provider defaults apply.
      LRoot := TJSONObject.Create;
      try
        LRoot.AddPair('model', LParams.Model);
        LRoot.AddPair('max_tokens', TJSONNumber.Create(LParams.MaxToken));
        if FSystemText <> '' then
          LRoot.AddPair('system', FSystemText);
        LMsg := TJSONObject.Create;
        LMsg.AddPair('role', 'user');
        LMsg.AddPair('content', APrompt);
        LMessages := TJSONArray.Create;
        LMessages.AddElement(LMsg);
        LRoot.AddPair('messages', LMessages);
        LBody := LRoot.ToJSON;
      finally
        LRoot.Free;
      end;

      LVersion := LParams.AnthropicVersion;
      if LVersion = '' then
        LVersion := CDefaultAnthropicVersion;
      LHttpClient.CustomHeaders[cClaude_CHeader_APIKey] := LParams.APIKey;
      LHttpClient.CustomHeaders[cClaude_CHeader_AnthropicVersion] := LVersion;
      LHttpClient.ContentType := cClaude_CHeader_JsonContentType;
      if LParams.Timeout <> 0 then
        LHttpClient.ConnectionTimeout := LParams.Timeout;

      LStream := TStringStream.Create(LBody, TEncoding.UTF8);
      try
        InvokeEvent(procedure begin ACallback.DoBeforeResponse; end);
        try
          LResp := LHttpClient.Post(
            TAIUtil.GetSafeFullURL(LParams.BaseURL, [LParams.Endpoint_Messages]),
            LStream);
        except
          on E: Exception do
          begin
            DoError(E.Message, EAIHTTPException);
            Exit;
          end;
        end;
        InvokeEvent(procedure begin ACallback.DoAfterResponse; end);
      finally
        LStream.Free;
      end;

      if LState.Cancelled then
        Exit;

      if TAIUtil.IsSuccessfulResponse(LResp) then
      begin
        LRaw := LResp.ContentAsString(TEncoding.UTF8);
        LText := '';
        LJSON := TJSONObject.ParseJSONValue(LRaw, False, True) as TJSONObject;
        try
          // Claude messages response: content[0].text
          LContent := LJSON.GetValue('content') as TJSONArray;
          if (LContent <> nil) and (LContent.Count > 0) then
            LText := (LContent.Items[0] as TJSONObject).GetValue<string>('text', '');
        finally
          LJSON.Free;
        end;
        try
          InvokeEvent(procedure begin ACallback.DoResponse(LText); end);
          InvokeEvent(procedure begin ACallback.DoFullResponse(LRaw); end);
        except
          on E: Exception do
            DoErrorChat(ACallback, E.Message, nil);
        end;
      end
      else
        DoErrorChat(ACallback, LResp.ContentAsString(TEncoding.UTF8), LResp);
    end);
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TAIClaudeDriverEx]);
end;

initialization
  RegisterClass(TAIClaudeDriverEx);

finalization
  UnRegisterClass(TAIClaudeDriverEx);

end.
