unit Replicate.ModelPicker;

// Design-time dialog: search the Replicate model catalog and pick a model for a
// Replicate bind source component. VCL (the IDE is VCL) and built entirely in
// code so there is no .dfm to keep in sync. Used by the component editor in
// Replicate.BindSource.Reg.
//
// Search uses Replicate's "search public models" endpoint: the HTTP QUERY
// method against https://api.replicate.com/v1/models with the search text as a
// plain-text body. Requires a valid API token.
//
// NOTE: not compiled in the authoring environment - expect build iteration.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls;

type
  TfrmReplicateModelPicker = class(TForm)
  private
    FTokenEdit: TEdit;
    FSearchEdit: TEdit;
    FSearchBtn: TButton;
    FList: TListView;
    FStatus: TLabel;
    FOKBtn: TButton;
    FCancelBtn: TButton;
    procedure BuildUI;
    procedure DoSearch(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    function SelectedModel: string;
  public
    // Shows the dialog. Returns True and updates AModel ('owner/name') when the
    // user picks a model. AToken is prefilled and returned (possibly edited).
    class function Execute(var AModel, AToken: string): Boolean;
  end;

implementation

uses
  System.NetEncoding,
  Winapi.Windows;

{ TfrmReplicateModelPicker }

procedure TfrmReplicateModelPicker.BuildUI;

  function MakeLabel(const ACaption: string; ALeft, ATop: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(ALeft, ATop + 3, 80, 21);
    Result.Caption := ACaption;
  end;

begin
  Caption := 'Pick a Replicate Model';
  Position := poScreenCenter;
  BorderStyle := bsSizeable;
  Width := 720;
  Height := 480;
  Constraints.MinWidth := 520;
  Constraints.MinHeight := 320;

  MakeLabel('API Token:', 12, 12);
  FTokenEdit := TEdit.Create(Self);
  FTokenEdit.Parent := Self;
  FTokenEdit.SetBounds(96, 12, 596, 23);
  FTokenEdit.Anchors := [akLeft, akTop, akRight];
  FTokenEdit.PasswordChar := '*';

  MakeLabel('Search:', 12, 44);
  FSearchEdit := TEdit.Create(Self);
  FSearchEdit.Parent := Self;
  FSearchEdit.SetBounds(96, 44, 500, 23);
  FSearchEdit.Anchors := [akLeft, akTop, akRight];
  FSearchEdit.TextHint := 'e.g. flux, whisper, upscale, llama';

  FSearchBtn := TButton.Create(Self);
  FSearchBtn.Parent := Self;
  FSearchBtn.SetBounds(604, 44, 88, 25);
  FSearchBtn.Anchors := [akTop, akRight];
  FSearchBtn.Caption := 'Search';
  FSearchBtn.Default := True;
  FSearchBtn.OnClick := DoSearch;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.SetBounds(12, 80, 680, 320);
  FList.Anchors := [akLeft, akTop, akRight, akBottom];
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnDblClick := ListDblClick;
  with FList.Columns.Add do begin Caption := 'Owner'; Width := 140; end;
  with FList.Columns.Add do begin Caption := 'Name'; Width := 170; end;
  with FList.Columns.Add do begin Caption := 'Description'; Width := 360; end;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(12, 412, 500, 21);
  FStatus.Anchors := [akLeft, akBottom];

  FOKBtn := TButton.Create(Self);
  FOKBtn.Parent := Self;
  FOKBtn.SetBounds(516, 408, 84, 27);
  FOKBtn.Anchors := [akRight, akBottom];
  FOKBtn.Caption := 'OK';
  FOKBtn.ModalResult := mrOk;

  FCancelBtn := TButton.Create(Self);
  FCancelBtn.Parent := Self;
  FCancelBtn.SetBounds(608, 408, 84, 27);
  FCancelBtn.Anchors := [akRight, akBottom];
  FCancelBtn.Caption := 'Cancel';
  FCancelBtn.ModalResult := mrCancel;
  FCancelBtn.Cancel := True;
end;

procedure TfrmReplicateModelPicker.DoSearch(Sender: TObject);
var
  LClient: THTTPClient;
  LReq: IHTTPRequest;
  LResp: IHTTPResponse;
  LBody: TStringStream;
  LJSON: TJSONObject;
  LResults: TJSONArray;
  LVal: TJSONValue;
  LObj: TJSONObject;
  LItem: TListItem;
  LOwner, LName, LDesc: string;
begin
  if Trim(FTokenEdit.Text) = '' then
  begin
    FStatus.Caption := 'Enter an API token to search.';
    Exit;
  end;

  FList.Items.Clear;
  FStatus.Caption := 'Searching...';
  FSearchBtn.Enabled := False;
  Screen.Cursor := crHourGlass;
  try
    LClient := THTTPClient.Create;
    LBody := TStringStream.Create(FSearchEdit.Text, TEncoding.UTF8);
    try
      LReq := LClient.GetRequest('QUERY', 'https://api.replicate.com/v1/models');
      LReq.SourceStream := LBody;
      LResp := LClient.Execute(LReq, nil,
        [TNetHeader.Create('Authorization', 'Bearer ' + Trim(FTokenEdit.Text)),
         TNetHeader.Create('Content-Type', 'text/plain')]);

      if LResp.StatusCode <> 200 then
      begin
        FStatus.Caption := Format('Search failed: HTTP %d', [LResp.StatusCode]);
        Exit;
      end;

      LJSON := TJSONObject.ParseJSONValue(LResp.ContentAsString) as TJSONObject;
      if LJSON = nil then
      begin
        FStatus.Caption := 'Search returned no parseable results.';
        Exit;
      end;
      try
        if not (LJSON.GetValue('results') is TJSONArray) then
        begin
          FStatus.Caption := 'No results.';
          Exit;
        end;
        LResults := LJSON.GetValue('results') as TJSONArray;
        for LVal in LResults do
        begin
          if not (LVal is TJSONObject) then Continue;
          LObj := LVal as TJSONObject;
          LOwner := LObj.GetValue<string>('owner', '');
          LName := LObj.GetValue<string>('name', '');
          LDesc := LObj.GetValue<string>('description', '');
          if LName = '' then Continue;
          LItem := FList.Items.Add;
          LItem.Caption := LOwner;
          LItem.SubItems.Add(LName);
          LItem.SubItems.Add(LDesc);
        end;
        FStatus.Caption := Format('%d model(s).', [FList.Items.Count]);
      finally
        LJSON.Free;
      end;
    finally
      LBody.Free;
      LClient.Free;
    end;
  except
    on E: Exception do
      FStatus.Caption := 'Error: ' + E.Message;
  end;
  Screen.Cursor := crDefault;
  FSearchBtn.Enabled := True;
end;

function TfrmReplicateModelPicker.SelectedModel: string;
begin
  Result := '';
  if (FList.Selected <> nil) and (FList.Selected.SubItems.Count >= 1) then
    Result := FList.Selected.Caption + '/' + FList.Selected.SubItems[0];
end;

procedure TfrmReplicateModelPicker.ListDblClick(Sender: TObject);
begin
  if SelectedModel <> '' then
    ModalResult := mrOk;
end;

class function TfrmReplicateModelPicker.Execute(var AModel, AToken: string): Boolean;
var
  LForm: TfrmReplicateModelPicker;
begin
  Result := False;
  LForm := TfrmReplicateModelPicker.CreateNew(nil);
  try
    LForm.BuildUI;
    LForm.FTokenEdit.Text := AToken;
    if AModel <> '' then
      LForm.FSearchEdit.Text := AModel;
    if LForm.ShowModal = mrOk then
    begin
      AToken := Trim(LForm.FTokenEdit.Text);
      if LForm.SelectedModel <> '' then
      begin
        AModel := LForm.SelectedModel;
        Result := True;
      end;
    end;
  finally
    LForm.Free;
  end;
end;

end.
